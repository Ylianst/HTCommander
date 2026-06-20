/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'data_broker.dart';

/// A client for the DataBroker that manages subscriptions for a specific component.
/// When disposed, all subscriptions are automatically removed.
///
/// Usage in a StatefulWidget:
/// ```dart
/// class _MyWidgetState extends State<MyWidget> {
///   final _broker = DataBrokerClient();
///
///   @override
///   void initState() {
///     super.initState();
///     _broker.subscribe(
///       deviceId: 2,
///       name: 'frequency',
///       callback: _onFrequencyChanged,
///     );
///   }
///
///   void _onFrequencyChanged(int deviceId, String name, Object? data) {
///     setState(() => _frequency = data as double?);
///   }
///
///   @override
///   void dispose() {
///     _broker.dispose();
///     super.dispose();
///   }
/// }
/// ```
class DataBrokerClient {
  bool _disposed = false;

  /// Creates a new DataBrokerClient instance.
  DataBrokerClient();

  /// Whether this client has been disposed.
  bool get isDisposed => _disposed;

  /// Subscribes to data changes for a specific device ID and name.
  ///
  /// [deviceId] - The device ID to subscribe to, or DataBroker.allDevices for all devices.
  /// [name] - The name/key to subscribe to, or DataBroker.allNames for all names.
  /// [callback] - The callback to invoke when data changes.
  void subscribe({
    required int deviceId,
    required String name,
    required DataCallback callback,
  }) {
    if (_disposed) {
      throw StateError('DataBrokerClient has been disposed');
    }
    DataBroker.subscribe(this, deviceId, name, callback);
  }

  /// Subscribes to data changes for a specific device ID and multiple names.
  ///
  /// [deviceId] - The device ID to subscribe to, or DataBroker.allDevices for all devices.
  /// [names] - The names/keys to subscribe to.
  /// [callback] - The callback to invoke when data changes.
  void subscribeMultiple({
    required int deviceId,
    required List<String> names,
    required DataCallback callback,
  }) {
    if (_disposed) {
      throw StateError('DataBrokerClient has been disposed');
    }
    for (final name in names) {
      DataBroker.subscribe(this, deviceId, name, callback);
    }
  }

  /// Subscribes to all data changes for a specific device ID.
  ///
  /// [deviceId] - The device ID to subscribe to, or DataBroker.allDevices for all devices.
  /// [callback] - The callback to invoke when data changes.
  void subscribeAll({
    int deviceId = DataBroker.allDevices,
    required DataCallback callback,
  }) {
    subscribe(
      deviceId: deviceId,
      name: DataBroker.allNames,
      callback: callback,
    );
  }

  /// Unsubscribes from a specific device ID and name.
  void unsubscribe(int deviceId, String name) {
    if (_disposed) return;
    DataBroker.unsubscribeSpecific(this, deviceId, name);
  }

  /// Unsubscribes from all subscriptions for this client.
  void unsubscribeAll() {
    if (_disposed) return;
    DataBroker.unsubscribe(this);
  }

  /// Dispatches data to the broker.
  ///
  /// [deviceId] - The device ID (use 0 for values that should persist).
  /// [name] - The name/key of the data.
  /// [data] - The data value.
  /// [store] - If true, the value is stored in the broker; if false, only broadcast.
  void dispatch({
    required int deviceId,
    required String name,
    required Object? data,
    bool store = true,
  }) {
    if (_disposed) return;
    DataBroker.dispatch(
      deviceId: deviceId,
      name: name,
      data: data,
      store: store,
    );
  }

  /// Gets a value from the broker.
  ///
  /// [deviceId] - The device ID.
  /// [name] - The name/key of the data.
  /// [defaultValue] - The default value to return if not found or type mismatch.
  T? getValue<T>(int deviceId, String name, [T? defaultValue]) {
    return DataBroker.getValue<T>(deviceId, name, defaultValue);
  }

  /// Gets a value from the broker as a dynamic object.
  Object? getValueDynamic(int deviceId, String name, [Object? defaultValue]) {
    return DataBroker.getValueDynamic(deviceId, name, defaultValue);
  }

  /// Gets a JSON value from the broker and parses it using the provided factory.
  ///
  /// [deviceId] - The device ID.
  /// [name] - The name/key of the data.
  /// [fromJson] - Factory function to create object from JSON map.
  T? getJsonValue<T>(
    int deviceId,
    String name,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = DataBroker.getValueDynamic(deviceId, name, null);
    if (data == null) return null;
    if (data is Map<String, dynamic>) {
      return fromJson(data);
    }
    return null;
  }

  /// Gets a JSON list value from the broker and parses each item.
  ///
  /// [deviceId] - The device ID.
  /// [name] - The name/key of the data.
  /// [fromJson] - Factory function to create each list item from JSON map.
  List<T>? getJsonListValue<T>(
    int deviceId,
    String name,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = DataBroker.getValueDynamic(deviceId, name, null);
    if (data == null) return null;
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map((e) => fromJson(e))
          .toList();
    }
    return null;
  }

  /// Checks if a value exists in the broker.
  bool hasValue(int deviceId, String name) {
    return DataBroker.hasValue(deviceId, name);
  }

  /// Publishes an informational log message to device 1 under "LogInfo".
  void logInfo(String msg) {
    if (_disposed) return;
    DataBroker.dispatch(deviceId: 1, name: 'LogInfo', data: msg, store: false);
  }

  /// Publishes an error log message to device 1 under "LogError".
  void logError(String msg) {
    if (_disposed) return;
    DataBroker.dispatch(deviceId: 1, name: 'LogError', data: msg, store: false);
  }

  /// Disposes the client and unsubscribes from all data changes.
  /// Must be called in the widget's dispose() method.
  void dispose() {
    if (!_disposed) {
      DataBroker.unsubscribe(this);
      _disposed = true;
    }
  }
}
