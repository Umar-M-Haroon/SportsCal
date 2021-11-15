#!/bin/sh

#  ci_post_clone.sh
#  SportsCal
#
#  Created by Umar Haroon on 11/15/21.
#  

echo "import Foundation\nstruct Constants {\n static let revenueAPIKey = \"" >> Constants.swift
echo $REVENUECAT_API_KEY >> Shared/Constants.swift
echo "\"\n}"
