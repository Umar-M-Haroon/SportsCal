#!/bin/zsh
# usage: run_tour.sh <tag> <panel>   tag: outer | inner | ...   panel: outer | inner
set -u
TAG=$1
PANEL=$2
S=/private/tmp/claude-501/-Users-umar-Developer-SportsCalMonoRepo-worktrees-main/9a15edc1-585b-4808-bdbb-f5ebd4a00e29/scratchpad
WT=${WT:-/Users/umar/Developer/SportsCalMonoRepo/worktrees/duo-support}
UDID=E9DDA573-CD05-4F46-B3E1-838EEB8BAB76
export DEVELOPER_DIR=/Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer
# Display UUIDs change every boot; find each panel by its native width.
panel_id() { xcrun simctl io $UDID enumerate | grep -B8 "Default width: $1\$" | awk '/UUID:/{print $2}' | tail -1; }
[ "$PANEL" = inner ] && DISPLAY_ID=$(panel_id 2007) || DISPLAY_ID=$(panel_id 1398)
echo "panel $PANEL -> $DISPLAY_ID"
OUT=$S/${SHOTS:-shots-sup}/$TAG

cd $WT
xcodebuild build-for-testing -project SportsCal/SportsCal.xcodeproj -scheme "SportsCal (iOS)" \
  -destination "id=$UDID" -derivedDataPath $S/${DD:-dd-ui-sup} CODE_SIGNING_ALLOWED=NO > $S/build-ui.log 2>&1 \
  || { echo "BUILD FAILED"; grep error: $S/build-ui.log | head; exit 1; }

rm -rf $S/$TAG.xcresult $OUT
mkdir -p $OUT

# Host-side screenshot server: answers each .req from the test.
(
  setopt NULL_GLOB
  while true; do
    for req in ~/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Data/Application/*/tmp/duo/*.req; do
      base=${req:t:r}
      xcrun simctl io $UDID screenshot --display=$DISPLAY_ID --mask=black $OUT/$base.png > /dev/null 2>&1
      rm -f $req
      touch ${req:h}/$base.done
    done
    [ -f $OUT/.stop ] && break
    sleep 0.2
  done
) &
SERVER=$!

TEST_RUNNER_DUO_TAG=$TAG TEST_RUNNER_DUO_SHOT_DIR=$OUT xcodebuild test-without-building \
  -project SportsCal/SportsCal.xcodeproj -scheme "SportsCal (iOS)" -destination "id=$UDID" \
  -derivedDataPath $S/${DD:-dd-ui-sup} -only-testing:SportsCalUITests/SportsCalUITests/testDuoTour \
  -resultBundlePath $S/$TAG.xcresult CODE_SIGNING_ALLOWED=NO > $S/test-$TAG.log 2>&1
echo "test exit $?"; grep -E "Test Case .*(passed|failed)|error:" $S/test-$TAG.log | tail -3
touch $OUT/.stop; wait $SERVER
rm -f $OUT/.stop

# accessibility trees
mkdir -p $OUT/trees
xcrun xcresulttool export attachments --path $S/$TAG.xcresult --output-path $OUT/trees > /dev/null 2>&1
ls $OUT/*.png | wc -l
