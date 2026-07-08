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
- Generate desktop update packages for self-update
- Create a GitHub Release with the installers attached
- Commit the update artifacts to `docs/` so the self-updater can find them

## Mac App Store

The macOS **App Store** build is not produced by CI. See
[AppStore.md](AppStore.md) for how to build and upload it manually with Xcode.

