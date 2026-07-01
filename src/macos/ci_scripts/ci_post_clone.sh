#!/bin/sh

# Fail this script if any subcommand fails.
set -e

echo "=== Starting ci_post_clone.sh ==="

# Install CocoaPods if not available.
if ! command -v pod &> /dev/null; then
  echo "Installing CocoaPods..."
  gem install cocoapods
fi

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH/src

# Install Flutter using git.
echo "Installing Flutter SDK..."
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Make Flutter available for the Xcode build phases too.
echo "export PATH=\"\$PATH:$HOME/flutter/bin\"" >> ~/.zprofile

# Install Flutter artifacts for desktop (macOS) platform.
flutter precache --macos

# Install dependencies and generate ephemeral files.
# flutter pub get generates macos/Flutter/ephemeral/ including FlutterGeneratedPluginSwiftPackage.
flutter pub get

# Install CocoaPods dependencies (window_manager, desktop_multi_window, etc.)
# This must run after flutter pub get which generates Flutter-Generated.xcconfig.
echo "Running pod install..."
cd $CI_PRIMARY_REPOSITORY_PATH/src/macos
pod install

echo "=== ci_post_clone.sh completed ==="
