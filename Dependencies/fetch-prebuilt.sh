#!/usr/bin/env bash

# Ensure we are in Dependencies directory
cd "$(dirname "$0")"

if [ ! -f ".last-prebuilt-fetch" ]; then
    echo "0,none" > .last-prebuilt-fetch
fi

LAST_FETCH=`cat .last-prebuilt-fetch | perl -n -e '/([0-9]*),([^ ]*)$/ && print $1'`
LAST_COMMIT=`cat .last-prebuilt-fetch | perl -n -e '/([0-9]*),([^ ]*)$/ && print $2'`

# fetch if last fetch was over 6 hours ago
if [[ $LAST_FETCH -lt $(expr $(date +%s) - 21600) ]] || [[ "$1" == "force" ]]; then
    echo "Checking for update"
    echo
    LATEST_COMMIT=`curl https://api.github.com/repos/SideStore/minimuxer/releases/latest | perl -n -e '/Commit: https:\\/\\/github\\.com\\/[^\\/]*\\/[^\\/]*\\/commit\\/([^"]*)/ && print $1'`
    echo
    echo "Last commit: $LAST_COMMIT"
    echo "Latest commit: $LATEST_COMMIT"
    if [[ "$LAST_COMMIT" != "$LATEST_COMMIT" ]]; then
        echo "Found update, downloading binaries"
        echo
        wget -O minimuxer.xcframework/ios-arm64/libminimuxer.a https://github.com/SideStore/minimuxer/releases/latest/download/libminimuxer.a
        wget -O minimuxer.xcframework/ios-arm64_x86_64-simulator/libminimuxer-sim.a https://github.com/SideStore/minimuxer/releases/latest/download/libminimuxer-sim.a
        wget -O minimuxer.xcframework/ios-arm64/Headers/minimuxer.h https://github.com/SideStore/minimuxer/releases/latest/download/minimuxer.h
        cp -v minimuxer.xcframework/ios-arm64/Headers/minimuxer.h minimuxer.xcframework/ios-arm64_x86_64-simulator/Headers/minimuxer.h
        echo
    else
        echo "Up-to-date"
    fi
    echo "$(date +%s),$LATEST_COMMIT" > .last-prebuilt-fetch
else
    echo "It hasn't been 6 hours and force was not specified, skipping update check"
fi
