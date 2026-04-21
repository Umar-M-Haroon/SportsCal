#!/bin/sh

#  ci_post_clone.sh
#  SportsCal
#
#  Created by Umar Haroon on 11/15/21.
#  
pwd
printf "import Foundation\nstruct Constants {\n	   static let revenueCatAPIKey = \"%s\"\n	   static let apiKey = \"%s\"\n	   static let adMobAppID = \"%s\"\n	   static let nativeAdUnitID = \"%s\"\n}" $REVENUECAT_API_KEY $SPORTSCAL_API_KEY $ADMOB_APP_ID $ADMOB_NATIVE_AD_UNIT_ID > ../Shared/Constants.swift
cat ../Shared/Constants.swift
