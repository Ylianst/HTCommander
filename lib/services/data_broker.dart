/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_broker_client.dart';

/// Callback type for data broker subscriptions.
/// Parameters: deviceId, name, data
typedef DataCallback = void Function(int deviceId, String name, Object? data);

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

    // Debug logging for channel change events
    if (name.startsWith('ChannelChange')) {
      debugPrint(
        'DataBroker.dispatch: $name for device $deviceId, data: $data',
      );
    }

    if (store) {
      final key = _DataKey(deviceId, name);
      broker._dataStore[key] = data;

      // Persist to SharedPreferences if device 0
      if (deviceId == 0 && broker._prefs != null) {
        broker._persistValue(name, data);
      }
    }

    // Find and invoke matching subscriptions
    final matchingSubscriptions = <_Subscription>[];
    for (final sub in broker._subscriptions) {
      final deviceMatches =
          (sub.deviceId == allDevices) || (sub.deviceId == deviceId);
      final nameMatches = (sub.name == allNames) || (sub.name == name);
      if (deviceMatches && nameMatches) {
        matchingSubscriptions.add(sub);
      }
    }

    // Debug logging for channel change events
    if (name.startsWith('ChannelChange')) {
      debugPrint(
        'DataBroker: Found ${matchingSubscriptions.length} matching subscriptions for $name (device $deviceId)',
      );
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
