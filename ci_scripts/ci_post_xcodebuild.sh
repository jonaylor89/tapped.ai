#!/bin/bash

# Upload symbols from Xcode Cloud's own archive; never rebuild just to obtain dSYMs.
set -euo pipefail

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "Skipping PostHog symbols: not an archive action."
  exit 0
fi
if [[ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]]; then
  echo "Skipping PostHog symbols: archive action did not succeed."
  exit 0
fi

: "${CI_ARCHIVE_PATH:?Xcode Cloud did not provide an archive path}"
: "${POSTHOG_CLI_API_KEY:?Set POSTHOG_CLI_API_KEY as a secret Xcode Cloud environment variable}"

ARCHIVE_PLIST="$CI_ARCHIVE_PATH/Info.plist"
DSYM_DIRECTORY="$CI_ARCHIVE_PATH/dSYMs"
APP_BINARY="$CI_ARCHIVE_PATH/Products/Applications/Tapped.app/Tapped"
MAIN_DSYM="$DSYM_DIRECTORY/Tapped.app.dSYM"
test -d "$MAIN_DSYM"

RELEASE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$ARCHIVE_PLIST")
RELEASE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE_PLIST")
if [[ "$RELEASE_NAME" != "com.intheloopstudio" || -z "$RELEASE_VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "error: Unexpected app identifier or missing version/build in archive metadata." >&2
  exit 1
fi

APP_UUIDS=$(xcrun dwarfdump --uuid "$APP_BINARY" | awk '/^UUID: / {print $2, $3}' | sort)
DSYM_UUIDS=$(xcrun dwarfdump --uuid "$MAIN_DSYM" | awk '/^UUID: / {print $2, $3}' | sort)
if [[ -z "$APP_UUIDS" || "$APP_UUIDS" != "$DSYM_UUIDS" ]]; then
  echo "error: Archive's main dSYM does not match its app binary." >&2
  exit 1
fi

# Install a checksum-pinned native CLI, without relying on Node/Homebrew on the Cloud runner.
CLI_VERSION="0.18.10"
case "$(uname -m)" in
  arm64)
    TARGET="aarch64-apple-darwin"
    SHA256="ac3610273be3c7bfd31b0e7f81d8b35119543bf66b99f669d1ec50abbb36d0da"
    ;;
  x86_64)
    TARGET="x86_64-apple-darwin"
    SHA256="31340b1936e36e93fbb6759a506f9cf2b55057bcdf5d18113d67f90d9ebe7e58"
    ;;
  *)
    echo "error: Unsupported Xcode Cloud architecture." >&2
    exit 1
    ;;
esac

CLI_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/tapped-posthog-cli.XXXXXX")
trap 'rm -rf "$CLI_DIRECTORY"' EXIT
curl --fail --silent --show-error --location --retry 3 \
  "https://releases.posthog.com/posthog-cli/v$CLI_VERSION/posthog-cli-$TARGET.tar.gz" \
  --output "$CLI_DIRECTORY/cli.tar.gz"
printf '%s  %s\n' "$SHA256" "$CLI_DIRECTORY/cli.tar.gz" | shasum -a 256 -c -
tar -xzf "$CLI_DIRECTORY/cli.tar.gz" -C "$CLI_DIRECTORY" --strip-components=1
CLI="$CLI_DIRECTORY/posthog-cli"
if [[ "$("$CLI" --version)" != "posthog-cli $CLI_VERSION" ]]; then
  echo "error: Installed PostHog CLI version does not match the pinned version." >&2
  exit 1
fi

export POSTHOG_CLI_HOST="https://us.posthog.com"
export POSTHOG_CLI_PROJECT_ID="75329"
echo "Uploading PostHog symbols for $RELEASE_NAME $RELEASE_VERSION ($BUILD_NUMBER)."
"$CLI" dsym upload \
  --directory "$DSYM_DIRECTORY" \
  --main-dsym Tapped.app.dSYM \
  --release-name "$RELEASE_NAME" \
  --release-version "$RELEASE_VERSION" \
  --build "$BUILD_NUMBER"
