#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH/src

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts for desktop (macOS) platform.
flutter precache --macos

# Install dependencies and generate ephemeral files.
flutter pub get

# Build the macOS app to ensure all generated files are created.
# This generates Flutter/ephemeral/ contents including FlutterGeneratedPluginSwiftPackage.
flutter build macos --config-only

# Install CocoaPods dependencies (flutter_pcm_sound, flutter_tts, etc.)
cd $CI_PRIMARY_REPOSITORY_PATH/src/macos
pod install
