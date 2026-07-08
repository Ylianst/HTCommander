# Uploading the macOS App Store Build with Xcode

The public releases (Windows MSI, Linux, and the macOS **DMG**) are built and
signed automatically by the GitHub Actions release workflow. The **Mac App
Store** build is *not* produced by CI — you build and upload it manually from
Xcode. This page describes that process.

## Why the App Store build is separate

- **App Sandbox is required** for the Mac App Store. The App Store variant is
  signed with [`src/macos/Runner/AppStore.entitlements`](../src/macos/Runner/AppStore.entitlements)
  (sandbox enabled), while the DMG uses `Release.entitlements` (sandbox
  disabled, so the in-app self-updater can replace the bundle).
- **The self-updater is disabled** in the App Store build via the
  `APP_STORE_BUILD` compile-time flag. App Store apps are updated by the App
  Store itself, and self-modifying code is not allowed. Passing
  `--dart-define=APP_STORE_BUILD=true` sets `kAppStoreBuild` in
  [`src/lib/services/update_service.dart`](../src/lib/services/update_service.dart),
  which hides the "Check for Updates" menu item and never initializes the
  updater.

App identity:

| | |
|---|---|
| Product name | `Handi-Talky Commander` |
| Bundle identifier | `com.meshcentral.htcommander` |
| Team ID | `CQ575Z873Y` |

## One-time setup

1. Have an **Apple Developer Program** membership and be signed in to Xcode
   (Xcode → Settings → Accounts) with that Apple ID.
2. In [App Store Connect](https://appstoreconnect.apple.com), create the macOS
   app record for bundle identifier `com.meshcentral.htcommander` (if it does
   not already exist).
3. Let Xcode manage signing automatically — it will create the required
   **Apple Distribution** and **Mac Installer Distribution** certificates and a
   **Mac App Store** provisioning profile on demand.

## Each release

### 1. Bump the version and build number

Edit `src/pubspec.yaml`:

```yaml
version: 0.2.0+2
```

App Store Connect **rejects duplicate build numbers**, so the number after `+`
must be higher than any build you have previously uploaded (even for the same
version string).

### 2. Build the Flutter assets with the App Store flag

From the `src` directory:

```bash
flutter build macos --release --dart-define=APP_STORE_BUILD=true
```

This compiles the Dart code with the self-updater disabled and persists the
`APP_STORE_BUILD` define into the generated Flutter Xcode config, so the Xcode
archive in the next step reuses it.

> Run this immediately before archiving. If you run any other `flutter build` /
> `flutter run` without the define in between, repeat this step so the define
> is not overwritten.

### 3. Point the archive at the App Store entitlements

Open the workspace in Xcode:

```bash
open src/macos/Runner.xcworkspace
```

- Select the **Runner** project → **Runner** target → **Build Settings**.
- Find **Code Signing Entitlements** for the **Release** configuration and set
  it to:

  ```
  Runner/AppStore.entitlements
  ```

  (The default is `Runner/Release.entitlements`, which has no sandbox and is
  only for the Developer ID / DMG build.)

> This is a temporary change for the App Store archive. **Revert it after
> uploading** (step 6) so you don't accidentally commit it — the DMG build must
> keep using `Release.entitlements`.

In **Signing & Capabilities**, make sure the team is set to your Apple
Developer team (`CQ575Z873Y`) and **Automatically manage signing** is enabled.

### 4. Archive

- Set the run destination to **My Mac**.
- Menu: **Product → Archive**.

Xcode builds and signs the app, then opens the **Organizer** with the new
archive.

### 5. Upload to App Store Connect

In the Organizer:

1. Select the archive → **Distribute App**.
2. Choose **App Store Connect** → **Upload**.
3. Accept the defaults (Xcode re-signs with the Apple Distribution and Mac
   Installer Distribution identities and uploads the package).
4. Wait for "Upload Successful".

### 6. Revert the entitlements setting

Undo the Build Settings change from step 3 so **Code Signing Entitlements**
(Release) points back to `Runner/Release.entitlements`. Confirm nothing is left
staged:

```bash
git -C src status
```

### 7. Submit for review

In App Store Connect, the uploaded build appears under the app's **TestFlight /
Builds** section after processing (a few minutes). Attach it to the app version
and submit for review.

## Verifying the build before upload

If you want to confirm the archived app is the correct variant:

- The **Help → Check for Updates** menu item and the **Check for Updates**
  button in the About dialog should be **absent** (self-updater disabled).
- The signed app should report the sandbox entitlement:

  ```bash
  codesign -d --entitlements :- "/path/to/Handi-Talky Commander.app" | grep app-sandbox
  ```

## Notes

- **Hardware access under the sandbox.** This app uses serial and Bluetooth to
  talk to the radio. The sandbox entitlements
  (`com.apple.security.device.serial`, `com.apple.security.device.bluetooth`)
  are included, but serial/USB access in particular is an area Apple review
  scrutinizes. Test the sandboxed build end-to-end with real hardware before
  submitting.
- **The DMG and App Store builds are independent.** The DMG (from CI) has the
  self-updater and points at the hosted `app-archive.json`; the App Store build
  has neither. They do not update each other.
