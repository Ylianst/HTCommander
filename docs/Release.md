# Making a New Release

## Steps

1. Update the version in `src/pubspec.yaml`:

   ```yaml
   version: 0.2.0+2
   ```

   The format is `<major>.<minor>.<patch>+<build_number>`. Increment the build number with each release.

2. Commit the version change:

   ```bash
   git add src/pubspec.yaml
   git commit -m "Bump version to 0.2.0"
   ```

3. Tag the release and push:

   ```bash
   git tag v0.2.0
   git push origin main --tags
   ```

This triggers the GitHub Actions workflow which will:

- Build Windows (MSI), Linux, and macOS (DMG) installers
- Build signed Android APKs separately for ARM64, ARMv7, and x86-64, plus an AAB for Google Play
- Generate desktop update packages for self-update
- Create a GitHub Release with the installers attached
- Commit the update artifacts to `docs/` so the self-updater can find them

The Android APK release assets are `HTCommander-arm64-v8a.apk`,
`HTCommander-armeabi-v7a.apk`, and `HTCommander-x86_64.apk`. The workflow uses
`flutter build apk --release --split-per-abi` instead of publishing a universal
APK. The AAB remains `htcommander-<version>.aab`.

## Mac App Store

The macOS **App Store** build is not produced by CI. See
[AppStore.md](AppStore.md) for how to build and upload it manually with Xcode.

