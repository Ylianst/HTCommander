/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_linux_pairing.dart - PIN pairing with a MeshCore companion on
// Linux through BlueZ. flutter_blue_plus cannot supply a passkey there, so
// HTCommander briefly registers its own BlueZ agent that answers with the PIN
// the user typed. Without a PIN, the desktop's own Bluetooth agent (if any)
// prompts instead.
//

import 'package:bluez/bluez.dart';

import 'meshcore_client.dart';

/// Answers BlueZ pairing requests with a fixed PIN.
class _PinAgent extends BlueZAgent {
  _PinAgent(this.pin);

  final String pin;

  @override
  Future<BlueZAgentPasskeyResponse> requestPasskey(BlueZDevice device) async {
    final passkey = int.tryParse(pin);
    return passkey == null
        ? BlueZAgentPasskeyResponse.rejected()
        : BlueZAgentPasskeyResponse.success(passkey);
  }

  @override
  Future<BlueZAgentPinCodeResponse> requestPinCode(BlueZDevice device) async =>
      BlueZAgentPinCodeResponse.success(pin);

  @override
  Future<BlueZAgentResponse> requestConfirmation(
    BlueZDevice device,
    int passkey,
  ) async => BlueZAgentResponse.success();

  @override
  Future<BlueZAgentResponse> requestAuthorization(BlueZDevice device) async =>
      BlueZAgentResponse.success();
}

BlueZDevice? _find(BlueZClient client, String address) {
  final target = address.toUpperCase();
  for (final d in client.devices) {
    if (d.address.toUpperCase() == target) return d;
  }
  return null;
}

/// Pairs with [address] unless already paired. Throws
/// [MeshCorePairingException] when the PIN is rejected.
Future<void> meshCoreLinuxPair(String address, String pin) async {
  final client = BlueZClient();
  var agentRegistered = false;
  try {
    await client.connect();
    final device = _find(client, address);
    // Unknown to BlueZ (not scanned yet) or already bonded: let the GATT
    // connection proceed; BlueZ pairs on demand if needed.
    if (device == null || device.paired) return;
    if (pin.isNotEmpty) {
      await client.registerAgent(
        _PinAgent(pin),
        capability: BlueZAgentCapability.keyboardOnly,
      );
      agentRegistered = true;
      try {
        await client.requestDefaultAgent();
      } catch (_) {
        // Another default agent is fine; BlueZ still asks the registering one.
      }
    }
    await device.pair().timeout(const Duration(seconds: 60));
  } on BlueZAuthenticationFailedException {
    throw const MeshCorePairingException(
      'Pairing failed. Check the PIN shown on the MeshCore device.',
    );
  } on BlueZAuthenticationRejectedException {
    throw const MeshCorePairingException(
      'Pairing failed. Check the PIN shown on the MeshCore device.',
    );
  } on BlueZAuthenticationCanceledException {
    throw const MeshCorePairingException('Pairing was canceled.');
  } on BlueZAlreadyExistsException {
    // Already paired.
  } finally {
    if (agentRegistered) {
      try {
        await client.unregisterAgent();
      } catch (_) {}
    }
    await client.close();
  }
}

/// Removes the bond with [address] so the next connection pairs again.
Future<bool> meshCoreLinuxForget(String address) async {
  final client = BlueZClient();
  try {
    await client.connect();
    final device = _find(client, address);
    if (device == null) return false;
    await device.adapter.removeDevice(device);
    return true;
  } catch (_) {
    return false;
  } finally {
    await client.close();
  }
}
