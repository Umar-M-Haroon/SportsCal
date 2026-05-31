#!/bin/sh

#  ci_post_clone.sh
#  SportsCal
#
#  Created by Umar Haroon on 11/15/21.
#  
pwd
if [ -z "$SENTRY_DSN" ]; then
    echo "WARNING: SENTRY_DSN env var is empty — Sentry crash reporting will be DISABLED in this build. Set it in Xcode Cloud environment variables."
fi
printf "import Foundation\nstruct Constants {\n	   static let revenueCatAPIKey = \"%s\"\n	   static let apiKey = \"%s\"\n	   static let adMobAppID = \"%s\"\n	   static let nativeAdUnitID = \"%s\"\n	   static let sentryDSN = \"%s\"\n}" $REVENUECAT_API_KEY $SPORTSCAL_API_KEY $ADMOB_APP_ID $ADMOB_NATIVE_AD_UNIT_ID $SENTRY_DSN > ../Shared/Constants.swift
cat ../Shared/Constants.swift
