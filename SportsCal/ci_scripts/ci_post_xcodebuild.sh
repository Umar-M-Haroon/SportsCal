#!/bin/sh
#
#  ci_post_xcodebuild.sh
#  SportsCal
#
#  Uploads debug symbols (dSYMs) to Sentry after an Xcode Cloud archive so that
#  App Store / TestFlight crash + App Hang reports symbolicate. Without this,
#  every Sentry stack frame for in-app code shows up as `?` (only the deepest
#  system frame, e.g. `_CFRelease` / `String.folding`, is visible), which makes
#  hangs and crashes effectively undiagnosable.
#
#  Required Xcode Cloud environment variables (Settings → Environment):
#    SENTRY_AUTH_TOKEN  — secret; a Sentry token with `project:releases` +
#                         `org:read` scope (Organization → Auth Tokens).
#  Optional (defaults shown):
#    SENTRY_ORG         — defaults to "mighty-panda-llc"
#    SENTRY_PROJECT     — defaults to "sports-cal"
#

# Only archive builds produce dSYMs worth uploading.
if [ "$CI_XCODEBUILD_ACTION" != "archive" ]; then
    echo "ci_post_xcodebuild: action is '$CI_XCODEBUILD_ACTION', not 'archive' — skipping dSYM upload."
    exit 0
fi

if [ -z "$SENTRY_AUTH_TOKEN" ]; then
    echo "WARNING: SENTRY_AUTH_TOKEN is empty — skipping dSYM upload. Set it as a secret in Xcode Cloud env vars to enable symbolication."
    exit 0
fi

SENTRY_ORG="${SENTRY_ORG:-mighty-panda-llc}"
SENTRY_PROJECT="${SENTRY_PROJECT:-sports-cal}"

if [ -z "$CI_ARCHIVE_PATH" ]; then
    echo "WARNING: CI_ARCHIVE_PATH is unset — cannot locate dSYMs. Skipping."
    exit 0
fi

DSYM_PATH="${CI_ARCHIVE_PATH}/dSYMs"
if [ ! -d "$DSYM_PATH" ]; then
    echo "WARNING: no dSYMs directory at $DSYM_PATH — skipping."
    exit 0
fi

echo "ci_post_xcodebuild: installing sentry-cli…"
curl -sL https://sentry.io/get-cli/ | INSTALL_DIR="$HOME/.local/bin" bash
export PATH="$HOME/.local/bin:$PATH"

echo "ci_post_xcodebuild: uploading dSYMs from $DSYM_PATH to $SENTRY_ORG/$SENTRY_PROJECT…"
sentry-cli debug-files upload \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    "$DSYM_PATH" \
    || echo "WARNING: dSYM upload failed (non-fatal — build continues)."

echo "ci_post_xcodebuild: done."
