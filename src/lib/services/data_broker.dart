/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodCall;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_broker_client.dart';

/// Callback type for data broker subscriptions.
/// Parameters: deviceId, name, data
typedef DataCallback = void Function(int deviceId, String name, Object? data);

/// The role a [DataBroker] plays in a multi-window (multi-process) session.
enum DataBrokerRole {
  /// Single window / no detached windows. Everything is process-local.
  standalone,

  /// Main window. Owns the authoritative data store and forwards every
  /// dispatch to all detached (child) windows.
  host,

  /// Detached window. Mirrors the host's data store (populated by a snapshot
  /// and kept up to date by forwarded dispatches) and forwards its own
  /// dispatches back to the host.
  client,
}

/// Converts a typed object into a JSON-safe map for cross-window transport.
typedef BrokerToJson = Map<String, dynamic> Function(Object? value);

/// Reconstructs a typed object from a JSON map received from another window.
typedef BrokerFromJson = Object? Function(Map<String, dynamic> json);

/// Pairs the encode/decode functions and the wire tag for a registered type.
class _BrokerSerializer {
  final String tag;
  final BrokerToJson toJson;
  final BrokerFromJson fromJson;

  const _BrokerSerializer(this.tag, this.toJson, this.fromJson);
}

/// A global data broker for dispatching and receiving data across components.
/// Supports device-specific and named data channels with optional persistence.
class DataBroker {
  /// Subscribe to all device IDs.
  static const int allDevices = -1;

  /// Subscribe to all names.
  static const String allNames = '*';

  /// Singleton instance
  static final DataBroker _instance = DataBroker._internal();

  /// Get the singleton instance.
  static DataBroker get instance => _instance;

  /// Internal data store: (deviceId, name) -> value
  final Map<_DataKey, Object?> _dataStore = {};

  /// List of active subscriptions
  final List<_Subscription> _subscriptions = [];

  /// Registered data handlers
  final Map<String, Object> _dataHandlers = {};

  /// SharedPreferences instance for persistence
  SharedPreferences? _prefs;

  /// Whether the broker has been initialized
  bool _initialized = false;

  /// The role this broker plays in a multi-window session.
  DataBrokerRole _role = DataBrokerRole.standalone;

  /// Host only: push channels to each detached child window, keyed by windowId.
  /// Used to forward dispatches from the main window to detached windows.
  final Map<String, WindowMethodChannel> _childChannels = {};

  /// Client only: the channel used to reach the host window.
  WindowMethodChannel? _clientToHost;

  /// Client only: the inbound push channel the host uses to reach this window.
  WindowMethodChannel? _clientInChannel;

  /// Client only: this window's own windowId.
  String? _selfWindowId;

  /// Host only: invoked when a detached window announces it is closing so the
  /// [WindowService] can drop it from its tracking. Set by the host.
  static void Function(String windowId)? onChildWindowDetached;

  /// Registered cross-window serializers keyed by runtime [Type].
  final Map<Type, _BrokerSerializer> _serializersByType = {};

  /// Registered cross-window serializers keyed by wire tag.
  final Map<String, _BrokerSerializer> _serializersByTag = {};

  /// Unidirectional channel name detached windows use to reach the host.
  static const String _hostChannelName = 'htcmd.broker.host';

  /// Unidirectional channel name the host uses to push data to a given window.
  static String _winChannelName(String windowId) =>
      'htcmd.broker.win.$windowId';

  /// Whether cross-window IPC is available on this platform.
  static bool get _ipcSupported {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// The current multi-window role of the broker.
  static DataBrokerRole get role => _instance._role;

  /// Whether this broker is the authoritative host (main window).
  static bool get isHost => _instance._role == DataBrokerRole.host;

  /// Whether this broker is a detached client window.
  static bool get isClient => _instance._role == DataBrokerRole.client;

  /// Private constructor for singleton
  DataBroker._internal();

  /// Initializes the data broker with persistent storage.
  /// Must be called once at app startup before using the broker.
  static Future<void> initialize() async {
    if (_instance._initialized) return;
    _instance._prefs = await SharedPreferences.getInstance();
    _instance._initialized = true;
  }

  /// Checks if the broker has been initialized.
  static bool get isInitialized => _instance._initialized;

  /// Dispatches data to the broker, optionally storing it and notifying subscribers.
  ///
  /// [deviceId] - The device ID (use 0 for values that should persist).
  /// [name] - The name/key of the data.
  /// [data] - The data value.
  /// [store] - If true, the value is stored in the broker; if false, only broadcast.
  static void dispatch({
    required int deviceId,
    required String name,
    required Object? data,
    bool store = true,
  }) {
    final broker = _instance;

    switch (broker._role) {
      case DataBrokerRole.standalone:
        broker._applyLocal(deviceId, name, data, store);
        break;
      case DataBrokerRole.host:
        // Apply on the host, then forward to every detached window.
        broker._applyLocal(deviceId, name, data, store);
        broker._forwardToChildren(deviceId, name, data, store);
        break;
      case DataBrokerRole.client:
        // Apply locally for immediate UI responsiveness, then forward to the
        // host so host-side handlers and the other windows are notified.
        broker._applyLocal(deviceId, name, data, store);
        broker._sendToHost(deviceId, name, data, store);
        break;
    }
  }

  /// Stores a value (when [store] is true) and notifies matching subscribers.
  ///
  /// This is the process-local part of a dispatch, shared by every role. It
  /// never crosses a window boundary.
  void _applyLocal(int deviceId, String name, Object? data, bool store) {
    if (store) {
      final key = _DataKey(deviceId, name);
      _dataStore[key] = data;

      // Persist to SharedPreferences if device 0. Only the host (or a
      // standalone window) owns persistence; clients rely on the host.
      if (deviceId == 0 &&
          _prefs != null &&
          _role != DataBrokerRole.client) {
        _persistValue(name, data);
      }
    }

    // Find and invoke matching subscriptions
    final matchingSubscriptions = <_Subscription>[];
    for (final sub in _subscriptions) {
      final deviceMatches =
          (sub.deviceId == allDevices) || (sub.deviceId == deviceId);
      final nameMatches = (sub.name == allNames) || (sub.name == name);
      if (deviceMatches && nameMatches) {
        matchingSubscriptions.add(sub);
      }
    }

    // Invoke callbacks
    for (final sub in matchingSubscriptions) {
      try {
        sub.callback(deviceId, name, data);
      } catch (e) {
        // Swallow exceptions from callbacks to prevent broker failure
        debugPrint('DataBroker: Callback error for ($deviceId, $name): $e');
      }
    }
  }

  /// Persists a value to SharedPreferences.
  void _persistValue(String name, Object? data) {
    if (_prefs == null) return;

    final prefKey = 'databroker_$name';

    if (data == null) {
      _prefs!.remove(prefKey);
    } else if (data is int) {
      _prefs!.setInt(prefKey, data);
    } else if (data is double) {
      _prefs!.setDouble(prefKey, data);
    } else if (data is String) {
      _prefs!.setString(prefKey, data);
    } else if (data is bool) {
      _prefs!.setBool(prefKey, data);
    } else if (data is List<String>) {
      _prefs!.setStringList(prefKey, data);
    } else {
      // Serialize complex types as JSON with type marker
      try {
        final typeName = _getSerializableTypeName(data.runtimeType);
        final json = jsonEncode(data);

        // Safety check: prevent overwriting non-empty data with empty collection
        if (data is Iterable && data.isEmpty) {
          final existingValue = _prefs!.getString(prefKey);
          if (existingValue != null &&
              existingValue.startsWith('~~JSON:') &&
              existingValue.length > 20) {
            debugPrint('DataBroker: Blocked saving empty collection for $name');
            return;
          }
        }

        final serialized = '~~JSON:$typeName:$json';
        _prefs!.setString(prefKey, serialized);
      } catch (e) {
        debugPrint('DataBroker: Failed to serialize $name: $e');
      }
    }
  }

  /// Loads a value from SharedPreferences.
  T? _loadPersistedValue<T>(String name, T? defaultValue) {
    if (_prefs == null) return defaultValue;

    final prefKey = 'databroker_$name';

    // Handle primitive types
    if (_isType<T, int>()) {
      final value = _prefs!.getInt(prefKey);
      if (value != null) return value as T;
    } else if (_isType<T, double>()) {
      final value = _prefs!.getDouble(prefKey);
      if (value != null) return value as T;
    } else if (_isType<T, String>()) {
      final value = _prefs!.getString(prefKey);
      if (value != null && !value.startsWith('~~JSON:')) {
        return value as T;
      }
    } else if (_isType<T, bool>()) {
      final value = _prefs!.getBool(prefKey);
      if (value != null) return value as T;
    } else if (_isListOfStrings<T>()) {
      final value = _prefs!.getStringList(prefKey);
      if (value != null) return value as T;
    }

    // Try to load serialized JSON for complex types
    final stringValue = _prefs!.getString(prefKey);
    if (stringValue != null && stringValue.startsWith('~~JSON:')) {
      try {
        // Parse: "~~JSON:TypeName:actual_json"
        final firstColon = stringValue.indexOf(':', 7); // Start after "~~JSON:"
        if (firstColon > 0) {
          final json = stringValue.substring(firstColon + 1);
          final decoded = jsonDecode(json);
          if (decoded is T) {
            return decoded;
          }
        }
      } catch (e) {
        debugPrint('DataBroker: JSON deserialization failed for $name: $e');
      }
    }

    return defaultValue;
  }

  /// Loads a value from SharedPreferences without a known target type.
  ///
  /// Used by [getValueDynamic]. Returns the raw stored primitive, or a decoded
  /// object/collection for values serialized with the `~~JSON:` marker.
  Object? _loadPersistedValueDynamic(String name) {
    if (_prefs == null) return null;

    final prefKey = 'databroker_$name';
    final raw = _prefs!.get(prefKey);
    if (raw == null) return null;

    if (raw is String && raw.startsWith('~~JSON:')) {
      try {
        // Parse: "~~JSON:TypeName:actual_json"
        final firstColon = raw.indexOf(':', 7); // Start after "~~JSON:"
        if (firstColon > 0) {
          final json = raw.substring(firstColon + 1);
          return jsonDecode(json);
        }
      } catch (e) {
        debugPrint('DataBroker: JSON deserialization failed for $name: $e');
      }
      return null;
    }

    return raw;
  }

  /// Helper to check if T matches a specific type (including nullable).
  static bool _isType<T, U>() {
    return T == U || null is T && T.toString() == '$U?';
  }

  /// Helper to check if type is `List<String>`.
  static bool _isListOfStrings<T>() {
    return T.toString() == 'List<String>' || T.toString() == 'List<String>?';
  }

  /// Gets a friendly type name for serialization purposes.
  static String _getSerializableTypeName(Type type) {
    return type.toString();
  }

  /// Gets a value from the broker.
  ///
  /// [deviceId] - The device ID.
  /// [name] - The name/key of the data.
  /// [defaultValue] - The default value to return if not found or type mismatch.
  static T? getValue<T>(int deviceId, String name, [T? defaultValue]) {
    final broker = _instance;
    final key = _DataKey(deviceId, name);

    if (broker._dataStore.containsKey(key)) {
      final value = broker._dataStore[key];
      if (value is T) {
        return value;
      }
      // Try conversion for compatible types
      if (value != null && T != Object && T != dynamic) {
        try {
          if (T == double && value is int) {
            return value.toDouble() as T;
          }
          if (T == int && value is double) {
            return value.toInt() as T;
          }
        } catch (_) {
          // Conversion failed, return default
        }
      }
      return defaultValue;
    }

    // For device 0, try loading from SharedPreferences if not in memory
    if (deviceId == 0 && broker._prefs != null) {
      final loadedValue = broker._loadPersistedValue<T>(name, defaultValue);
      if (loadedValue != null) {
        // Cache in memory for subsequent access
        broker._dataStore[key] = loadedValue;
        return loadedValue;
      }
    }

    return defaultValue;
  }

  /// Gets a value from the broker as a dynamic object.
  static Object? getValueDynamic(
    int deviceId,
    String name, [
    Object? defaultValue,
  ]) {
    final broker = _instance;
    final key = _DataKey(deviceId, name);

    if (broker._dataStore.containsKey(key)) {
      return broker._dataStore[key];
    }

    // For device 0, try loading from SharedPreferences if not in memory.
    if (deviceId == 0 && broker._prefs != null) {
      final loadedValue = broker._loadPersistedValueDynamic(name);
      if (loadedValue != null) {
        // Cache in memory for subsequent access.
        broker._dataStore[key] = loadedValue;
        return loadedValue;
      }
    }

    return defaultValue;
  }

  /// Checks if a value exists in the broker.
  static bool hasValue(int deviceId, String name) {
    final key = _DataKey(deviceId, name);
    return _instance._dataStore.containsKey(key);
  }

  /// Removes a value from the broker.
  /// Returns true if the value was removed, false if it didn't exist.
  static bool removeValue(int deviceId, String name) {
    final broker = _instance;
    final key = _DataKey(deviceId, name);
    final removed = broker._dataStore.remove(key) != null;

    // Also remove from SharedPreferences if device 0
    if (deviceId == 0 && broker._prefs != null) {
      broker._prefs!.remove('databroker_$name');
    }

    return removed;
  }

  /// Gets all stored values for a specific device.
  static Map<String, Object?> getDeviceValues(int deviceId) {
    final result = <String, Object?>{};
    for (final entry in _instance._dataStore.entries) {
      if (entry.key.deviceId == deviceId) {
        result[entry.key.name] = entry.value;
      }
    }
    return result;
  }

  /// Clears all stored data for a specific device.
  static void clearDevice(int deviceId) {
    _instance._dataStore.removeWhere((key, _) => key.deviceId == deviceId);
  }

  /// Deletes all data for a specific device, dispatching null values to all
  /// subscribers before removing the data from storage.
  static void deleteDevice(int deviceId) {
    final keysToRemove = _instance._dataStore.keys
        .where((key) => key.deviceId == deviceId)
        .toList();

    // Dispatch null for each key to notify subscribers
    for (final key in keysToRemove) {
      dispatch(
        deviceId: key.deviceId,
        name: key.name,
        data: null,
        store: false,
      );
    }

    // Remove all values for the device from storage
    for (final key in keysToRemove) {
      _instance._dataStore.remove(key);
    }
  }

  /// Clears all stored data and subscriptions. Use with caution.
  static void reset() {
    _instance._dataStore.clear();
    _instance._subscriptions.clear();
  }

  /// Internal method to subscribe. Called by DataBrokerClient.
  static void subscribe(
    DataBrokerClient client,
    int deviceId,
    String name,
    DataCallback callback,
  ) {
    _instance._subscriptions.add(
      _Subscription(
        client: client,
        deviceId: deviceId,
        name: name,
        callback: callback,
      ),
    );
  }

  /// Internal method to unsubscribe all subscriptions for a client.
  static void unsubscribe(DataBrokerClient client) {
    _instance._subscriptions.removeWhere((s) => s.client == client);
  }

  /// Internal method to unsubscribe a specific subscription for a client.
  static void unsubscribeSpecific(
    DataBrokerClient client,
    int deviceId,
    String name,
  ) {
    _instance._subscriptions.removeWhere(
      (s) => s.client == client && s.deviceId == deviceId && s.name == name,
    );
  }

  // ========== Data Handlers ==========

  /// Adds a data handler to the broker.
  /// Dispatches a "DataHandlerAdded" event on device 0 with the handler name.
  /// Returns true if added successfully, false if a handler with that name already exists.
  static bool addDataHandler(String name, Object handler) {
    if (name.isEmpty) {
      throw ArgumentError.notNull('name');
    }

    final broker = _instance;
    if (broker._dataHandlers.containsKey(name)) {
      return false;
    }

    broker._dataHandlers[name] = handler;
    dispatch(deviceId: 0, name: 'DataHandlerAdded', data: name, store: false);
    return true;
  }

  /// Gets a data handler by name.
  static T? getDataHandler<T>(String name) {
    if (name.isEmpty) return null;
    final handler = _instance._dataHandlers[name];
    if (handler is T) {
      return handler;
    }
    return null;
  }

  /// Gets a data handler by name as dynamic.
  static Object? getDataHandlerDynamic(String name) {
    if (name.isEmpty) return null;
    return _instance._dataHandlers[name];
  }

  /// Removes a data handler by name.
  /// Dispatches a "DataHandlerRemoved" event on device 0 with the handler name.
  /// Returns true if removed, false if not found.
  static bool removeDataHandler(String name) {
    if (name.isEmpty) return false;

    final handler = _instance._dataHandlers.remove(name);
    if (handler != null) {
      dispatch(
        deviceId: 0,
        name: 'DataHandlerRemoved',
        data: name,
        store: false,
      );
      return true;
    }
    return false;
  }

  /// Checks if a data handler with the specified name exists.
  static bool hasDataHandler(String name) {
    if (name.isEmpty) return false;
    return _instance._dataHandlers.containsKey(name);
  }

  /// Removes all data handlers.
  static void removeAllDataHandlers() {
    _instance._dataHandlers.clear();
  }

  // ========== Cross-window serialization ==========

  /// Registers a serializer so values of type [T] can be sent to and rebuilt in
  /// detached windows. Must be called on every process (host and clients)
  /// before any windows are attached.
  ///
  /// [tag] is a short, unique identifier written on the wire.
  static void registerSerializer<T>(
    String tag,
    Map<String, dynamic> Function(T value) toJson,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final serializer = _BrokerSerializer(
      tag,
      (value) => toJson(value as T),
      (json) => fromJson(json),
    );
    _instance._serializersByType[T] = serializer;
    _instance._serializersByTag[tag] = serializer;
  }

  /// Encodes a broker value to a JSON string safe for the platform channel.
  /// Returns null if the value could not be encoded (e.g. no serializer for a
  /// custom type); the caller then skips forwarding that value.
  String? _encode(Object? value) {
    try {
      return jsonEncode(value, toEncodable: _toEncodable);
    } catch (e) {
      debugPrint('DataBroker: unable to encode value for transport: $e');
      return null;
    }
  }

  /// Decodes a JSON string received from another window back into broker data,
  /// reconstructing registered types via their serializers.
  Object? _decode(String? payload) {
    if (payload == null) return null;
    try {
      return jsonDecode(payload, reviver: _reviver);
    } catch (e) {
      debugPrint('DataBroker: unable to decode value from transport: $e');
      return null;
    }
  }

  Object? _toEncodable(Object? object) {
    if (object == null) return null;
    final serializer = _serializersByType[object.runtimeType];
    if (serializer != null) {
      return {'__t': serializer.tag, '__v': serializer.toJson(object)};
    }
    // Fall back to a plain toJson() if the object provides one. It will arrive
    // as a Map on the other side (consumers handle the Map form).
    try {
      final dynamic dyn = object;
      final result = dyn.toJson();
      if (result != null) return result;
    } catch (_) {
      // No toJson available.
    }
    throw UnsupportedError(
      'DataBroker: no serializer registered for ${object.runtimeType}',
    );
  }

  Object? _reviver(Object? key, Object? value) {
    if (value is Map && value.length == 2 && value.containsKey('__t')) {
      final tag = value['__t'];
      final serializer = tag is String ? _serializersByTag[tag] : null;
      if (serializer != null) {
        final inner = value['__v'];
        if (inner is Map<String, dynamic>) return serializer.fromJson(inner);
        if (inner is Map) {
          return serializer.fromJson(Map<String, dynamic>.from(inner));
        }
      }
    }
    return value;
  }

  // ========== Cross-window transport (host + client) ==========

  /// Promotes this broker to the authoritative host and starts listening for
  /// detached windows. Safe to call more than once; no-op off desktop.
  static Future<void> becomeHost() async {
    final broker = _instance;
    if (!_ipcSupported || broker._role == DataBrokerRole.host) return;
    broker._role = DataBrokerRole.host;
    try {
      final channel = WindowMethodChannel(
        _hostChannelName,
        mode: ChannelMode.unidirectional,
      );
      await channel.setMethodCallHandler(broker._onHostCall);
    } catch (e) {
      debugPrint('DataBroker: failed to start host channel: $e');
    }
  }

  /// Turns this broker into a detached client bound to the host window and
  /// registers the inbound push channel. Call [requestSnapshot] afterwards.
  static Future<void> becomeClient(String selfWindowId) async {
    final broker = _instance;
    if (!_ipcSupported) return;
    broker._role = DataBrokerRole.client;
    broker._selfWindowId = selfWindowId;
    broker._initialized = true;
    try {
      broker._clientToHost = WindowMethodChannel(
        _hostChannelName,
        mode: ChannelMode.unidirectional,
      );
      final inChannel = WindowMethodChannel(
        _winChannelName(selfWindowId),
        mode: ChannelMode.unidirectional,
      );
      broker._clientInChannel = inChannel;
      await inChannel.setMethodCallHandler(broker._onClientCall);
    } catch (e) {
      debugPrint('DataBroker: failed to start client channel: $e');
    }
  }

  /// Host only: registers a detached window so dispatches are forwarded to it.
  static void registerChildWindow(String windowId) {
    final broker = _instance;
    if (!_ipcSupported) return;
    broker._childChannels[windowId] = WindowMethodChannel(
      _winChannelName(windowId),
      mode: ChannelMode.unidirectional,
    );
  }

  /// Host only: stops forwarding dispatches to a detached window.
  static void unregisterChildWindow(String windowId) {
    _instance._childChannels.remove(windowId);
  }

  /// Client only: gracefully detaches this window from the host before its
  /// engine is torn down. Announces the close to the host (so the host stops
  /// forwarding dispatches to a channel whose engine is about to disappear —
  /// which can otherwise crash the whole application) and tears down this
  /// window's own broker channels. Safe to call more than once.
  static Future<void> shutdownClient() async {
    final broker = _instance;
    if (broker._role != DataBrokerRole.client) return;

    final channel = broker._clientToHost;
    final id = broker._selfWindowId;
    if (channel != null && id != null) {
      try {
        await channel.invokeMethod('detach', {'windowId': id});
      } catch (_) {
        // Host may already be gone; nothing more we can do.
      }
    }

    try {
      await broker._clientInChannel?.setMethodCallHandler(null);
    } catch (_) {
      // Ignore: the inbound handler may already be unregistered.
    }
    broker._clientInChannel = null;
    broker._clientToHost = null;
  }

  /// Client only: asks the host for a full snapshot of its data store and
  /// applies it locally. Retries briefly to tolerate host/child start-up races.
  static Future<void> requestSnapshot() async {
    final broker = _instance;
    final channel = broker._clientToHost;
    if (channel == null) return;
    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        final result = await channel.invokeMethod<dynamic>('snapshot');
        if (result is List) {
          for (final entry in result) {
            if (entry is Map) {
              final deviceId = entry['deviceId'] as int;
              final name = entry['name'] as String;
              final data = broker._decode(entry['payload'] as String?);
              broker._applyLocal(deviceId, name, data, true);
            }
          }
        }
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    debugPrint('DataBroker: snapshot request timed out');
  }

  /// Host handler: services `dispatch` and `snapshot` calls from detached
  /// windows.
  Future<dynamic> _onHostCall(MethodCall call) async {
    switch (call.method) {
      case 'dispatch':
        final args = (call.arguments as Map).cast<String, Object?>();
        final deviceId = args['deviceId'] as int;
        final name = args['name'] as String;
        final store = args['store'] as bool? ?? true;
        final from = args['from'] as String?;
        final data = _decode(args['payload'] as String?);
        // Apply on the host (notifies host-side handlers and subscribers),
        // then forward to every OTHER detached window.
        _applyLocal(deviceId, name, data, store);
        _forwardToChildren(deviceId, name, data, store, exclude: from);
        return null;
      case 'snapshot':
        return _buildSnapshot();
      case 'detach':
        // A detached window is closing. Stop forwarding to it immediately so we
        // never invoke a method channel on an engine that is being destroyed.
        final args = (call.arguments as Map).cast<String, Object?>();
        final windowId = args['windowId'] as String?;
        if (windowId != null) {
          _childChannels.remove(windowId);
          onChildWindowDetached?.call(windowId);
        }
        return null;
    }
    return null;
  }

  /// Client handler: applies data pushed from the host.
  Future<dynamic> _onClientCall(MethodCall call) async {
    if (call.method == 'onData') {
      final args = (call.arguments as Map).cast<String, Object?>();
      final deviceId = args['deviceId'] as int;
      final name = args['name'] as String;
      final store = args['store'] as bool? ?? true;
      final data = _decode(args['payload'] as String?);
      _applyLocal(deviceId, name, data, store);
    }
    return null;
  }

  /// Host only: builds a codec-safe snapshot of the entire data store.
  List<Map<String, Object?>> _buildSnapshot() {
    final out = <Map<String, Object?>>[];
    _dataStore.forEach((key, value) {
      final payload = _encode(value);
      if (payload == null && value != null) return; // unencodable, skip
      out.add({
        'deviceId': key.deviceId,
        'name': key.name,
        'payload': payload,
      });
    });
    return out;
  }

  /// Host only: forwards a dispatch to all detached windows (optionally
  /// excluding the window that originated it).
  void _forwardToChildren(
    int deviceId,
    String name,
    Object? data,
    bool store, {
    String? exclude,
  }) {
    if (_childChannels.isEmpty) return;
    final payload = _encode(data);
    if (payload == null && data != null) return; // unencodable, skip
    final args = {
      'deviceId': deviceId,
      'name': name,
      'payload': payload,
      'store': store,
    };
    _childChannels.forEach((windowId, channel) {
      if (windowId == exclude) return;
      channel.invokeMethod('onData', args).catchError((Object e) {
        // Window may not have registered its handler yet, or has closed.
        return null;
      });
    });
  }

  /// Client only: forwards a locally originated dispatch to the host.
  void _sendToHost(int deviceId, String name, Object? data, bool store) {
    final channel = _clientToHost;
    if (channel == null) return;
    final payload = _encode(data);
    if (payload == null && data != null) return; // unencodable, skip
    channel.invokeMethod('dispatch', {
      'deviceId': deviceId,
      'name': name,
      'payload': payload,
      'store': store,
      'from': _selfWindowId,
    }).catchError((Object e) {
      debugPrint('DataBroker: failed to forward dispatch to host: $e');
      return null;
    });
  }
}


/// Internal structure for storing data keys.
class _DataKey {
  final int deviceId;
  final String name;

  const _DataKey(this.deviceId, this.name);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DataKey &&
        other.deviceId == deviceId &&
        other.name == name;
  }

  @override
  int get hashCode => deviceId.hashCode ^ name.hashCode;
}

/// Internal subscription information.
class _Subscription {
  final DataBrokerClient client;
  final int deviceId;
  final String name;
  final DataCallback callback;

  const _Subscription({
    required this.client,
    required this.deviceId,
    required this.name,
    required this.callback,
  });
}
