#!/bin/bash

# Usage
# Must be an absolute path

# ./quick-resign.sh  "origin.ipa path"  "resign.ipa path"


INPUT_PATH=$1
OUTPUT_PATH=$2

if [[ ! $2 ]];then
	OUTPUT_PATH=$PWD
fi

cp -rf $INPUT_PATH ../TargetApp/
cd ../../
xcodebuild | xcpretty
cd LatestBuild
./createIPA.command
cp -rf Target.ipa $OUTPUT_PATH
exit 0