#!/bin/sh

#  ci_post_clone.sh
#  SportsCal
#
#  Created by Umar Haroon on 11/15/21.
#  
pwd
printf "import Foundation\nstruct Constants {\n	   static let revenueCatAPIKey = \"%s\"\n}" $REVENUECAT_API_KEY > ../Shared/Constants.swift
cat ../Shared/Constants.swift
