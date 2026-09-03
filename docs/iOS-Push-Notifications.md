# iOS push notification setup

HTCommander receives iOS notifications through Firebase Messaging in the app,
but HTCloudServer sends them directly to Apple Push Notification service (APNs).
The app therefore registers its raw APNs device token with the server. Do not
replace it with an FCM token on the server.

## Prerequisites

- Apple Developer Program access for team `CQ575Z873Y`.
- The App ID and Firebase iOS app both use the bundle ID
  `com.meshcentral.htcommander`.
- Access to the Firebase project already used by the Android app.
- A physical iPhone. Push notification testing should not rely on the simulator.

## 1. Enable push in Apple Developer

1. Open **Certificates, Identifiers & Profiles** in the Apple Developer portal.
2. Select **Identifiers**, then the App ID for
   `com.meshcentral.htcommander`.
3. Enable **Push Notifications** and save the identifier.
4. Refresh the app's development and distribution provisioning profiles. With
   Xcode automatic signing, opening the project and building normally refreshes
   them.
5. Select **Keys**, create a key with **Apple Push Notifications service
   (APNs)** enabled, and download the `.p8` file. Apple permits downloading it
   only once.
6. Record the Key ID shown for the key and the Team ID from the developer
   membership page.

An APNs signing key is server-only. Never add the `.p8` file to this repository
or ship it in the app.

## 2. Add the Firebase iOS configuration

The Firebase Messaging Flutter plugin performs the iOS notification registration
and callback integration. It needs a Firebase iOS app configuration even though
HTCloudServer, rather than Firebase, sends the APNs request.

1. In the Firebase project used by
   `src/android/app/google-services.json`, add an **iOS app**.
2. Enter the exact Apple bundle ID `com.meshcentral.htcommander`.
3. Download `GoogleService-Info.plist`.
4. Open `src/ios/Runner.xcworkspace` in Xcode.
5. Drag the plist into the **Runner** group. Select **Copy items if needed**, add
   it to the **Runner** target, and verify it appears in **Build Phases > Copy
   Bundle Resources**.
6. Commit `src/ios/Runner/GoogleService-Info.plist`. Firebase client
   configuration is not a server credential; keeping it beside Android's
   checked-in configuration makes builds reproducible.

Uploading the APNs `.p8` key to Firebase is not required for this architecture.
HTCloudServer uses that key directly.

## 3. Verify Xcode capabilities

The project contains the required entitlement and background mode. In Xcode,
select **Runner > Signing & Capabilities** and verify:

- **Push Notifications** is present.
- **Background Modes > Remote notifications** is checked.
- The selected team is `CQ575Z873Y` and automatic signing reports no errors.

A Debug build receives a sandbox APNs token. TestFlight and App Store builds
receive production APNs tokens. A token only works against the matching APNs
environment.

## 4. Configure HTCloudServer

Copy the downloaded key to a location readable only by the server account, for
example:

```bash
install -m 600 AuthKey_XXXXXXXXXX.p8 /opt/htcloudserver/data/
```

Set the iOS sections in HTCloudServer's `config.ini`:

```ini
[messaging.ios]
enabled = true

[messaging.ios.apns]
keyFile = /opt/htcloudserver/data/AuthKey_XXXXXXXXXX.p8
keyId = XXXXXXXXXX
teamId = CQ575Z873Y
bundleId = com.meshcentral.htcommander
production = true
```

Use `production = true` for TestFlight/App Store builds. For a local Debug build,
use `production = false`; switch it back before serving production clients. The
current server configuration selects one APNs environment at a time, so testing
a TestFlight build against the production server is the least disruptive path.

Restart HTCloudServer after changing the configuration. It validates all four
APNs fields at startup. Confirm that `/health` responds and watch the server log
while registering the device. No server source change is required: the push
dispatcher already routes `platform: "ios"` registrations to its APNs HTTP/2
provider.

## 5. End-to-end test

1. Install a TestFlight or signed device build. Push does not work with an
   unsigned build.
2. In iOS Settings, allow notifications for HTCommander.
3. In HTCommander, configure a callsign, enable APRS-IS with its valid passcode,
   and enable **Push notifications (aprs.meshcentral.com)** in APRS settings.
4. Confirm the server records an iOS registration for that callsign and SSID.
5. Fully background the app and send an APRS message to the station from another
   station/account.
6. Verify the notification appears. Tap it and confirm HTCommander syncs and
   opens the sender's conversation.
7. Force-quit and relaunch once to verify backlog sync independently of live
   push delivery.

## Troubleshooting

- `BadDeviceToken`: the server's `production` setting does not match the build
  that produced the token, or the token is malformed.
- `DeviceTokenNotForTopic`: `bundleId` does not exactly match
  `com.meshcentral.htcommander`, or the key/team belongs to a different App ID.
- No token: verify notification permission, the Push Notifications capability,
  signing profile, and that `GoogleService-Info.plist` is bundled in Runner.
- Firebase initialization error: verify the plist came from the matching iOS
  app in Firebase and is included in the Runner target.
- Registration succeeds but no notification arrives: check that the server log
  selected the APNs provider and inspect the APNs status/reason in the warning.
- Permission was previously denied: re-enable notifications in the iOS Settings
  app; iOS does not show the permission prompt a second time.
