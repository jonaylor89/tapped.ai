#!/bin/sh

# Xcode Cloud post-clone step for the native SwiftUI app.
# No Flutter or CocoaPods: dependencies are SPM-only and pinned by the committed Package.resolved.

# Fail this script if any subcommand fails or uses an unset variable.
set -eu

# Xcode Cloud discovers ci_scripts only at the repository root.
cd "$CI_PRIMARY_REPOSITORY_PATH/com.intheloopstudio"
test -d Tapped.xcodeproj

# Tapped.xcodeproj is committed; do not generate it in CI.

# Resolve packages strictly from the committed Package.resolved.
xcodebuild -resolvePackageDependencies \
  -project Tapped.xcodeproj \
  -scheme Runner \
  -disableAutomaticPackageResolution

exit 0
