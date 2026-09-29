#!/bin/sh

# Xcode Cloud post-clone step for the native SwiftUI app.
# No Flutter or CocoaPods: dependencies are SPM-only and pinned by the committed Package.resolved.

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd "$CI_PRIMARY_REPOSITORY_PATH/com.intheloopstudio.ios"

# Tapped.xcodeproj is committed, but regenerate it when project.yml is present so the two never drift.
if [ -f project.yml ]; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
  xcodegen generate
fi

# Resolve packages strictly from the committed Package.resolved.
xcodebuild -resolvePackageDependencies \
  -project Tapped.xcodeproj \
  -scheme Tapped \
  -disableAutomaticPackageResolution

exit 0
