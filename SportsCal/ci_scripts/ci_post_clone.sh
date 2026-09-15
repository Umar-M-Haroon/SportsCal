#!/bin/sh

#  ci_post_clone.sh
#  SportsCal
#
#  Created by Umar Haroon on 11/15/21.
#
pwd

# Fail the build rather than ship a binary with blank secrets. An empty
# SPORTSCAL_API_KEY compiles fine but every API call 403s — that is how 3.2
# shipped showing "No games fetched" to everyone.
missing=""
for var in SPORTSCAL_API_KEY REVENUECAT_API_KEY ADMOB_APP_ID ADMOB_NATIVE_AD_UNIT_ID; do
    eval "value=\${$var}"
    if [ -z "$value" ]; then
        missing="$missing $var"
    fi
done
if [ -n "$missing" ]; then
    echo "error: missing Xcode Cloud environment variables:$missing — set them on this workflow (App Store Connect → Xcode Cloud → Manage Workflows → Environment)."
    exit 1
fi

if [ -z "$SENTRY_DSN" ]; then
    echo "WARNING: SENTRY_DSN env var is empty — Sentry crash reporting will be DISABLED in this build. Set it in Xcode Cloud environment variables."
fi

# Quoted arguments: an unquoted empty variable drops out of printf's argument
# list and shifts every later value into the wrong constant.
printf "import Foundation\nstruct Constants {\n	   static let revenueCatAPIKey = \"%s\"\n	   static let apiKey = \"%s\"\n	   static let adMobAppID = \"%s\"\n	   static let nativeAdUnitID = \"%s\"\n	   static let sentryDSN = \"%s\"\n}" "$REVENUECAT_API_KEY" "$SPORTSCAL_API_KEY" "$ADMOB_APP_ID" "$ADMOB_NATIVE_AD_UNIT_ID" "$SENTRY_DSN" > ../Shared/Constants.swift
echo "Generated ../Shared/Constants.swift"
