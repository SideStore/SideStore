#!/usr/bin/env bash

# Ensure we are in Dependencies directory
cd "$(dirname "$0")"

check_for_update() {
    if [ ! -f ".last-prebuilt-fetch-$1" ]; then
        echo "0,none" > ".last-prebuilt-fetch-$1"
    fi

    LAST_FETCH=`cat .last-prebuilt-fetch-$1 | perl -n -e '/([0-9]*),([^ ]*)$/ && print $1'`
    LAST_COMMIT=`cat .last-prebuilt-fetch-$1 | perl -n -e '/([0-9]*),([^ ]*)$/ && print $2'`

    # fetch if last fetch was over 6 hours ago
    if [[ $LAST_FETCH -lt $(expr $(date +%s) - 21600) ]] || [[ "$2" == "force" ]]; then
        echo "Checking $1 for update"
        echo
        LATEST_COMMIT=`curl https://api.github.com/repos/SideStore/$1/releases/latest | perl -n -e '/Commit: https:\\/\\/github\\.com\\/[^\\/]*\\/[^\\/]*\\/commit\\/([^"]*)/ && print $1'`
        echo
        echo "Last commit: $LAST_COMMIT"
        echo "Latest commit: $LATEST_COMMIT"
        if [[ "$LAST_COMMIT" != "$LATEST_COMMIT" ]]; then
            echo "Found update, downloading binaries"
            echo
            wget -O "$1.xcframework/ios-arm64/lib$1.a" "https://github.com/SideStore/$1/releases/latest/download/lib$1.a"
            wget -O "$1.xcframework/ios-arm64_x86_64-simulator/lib$1-sim.a" "https://github.com/SideStore/$1/releases/latest/download/lib$1-sim.a"
            wget -O "$1.xcframework/ios-arm64/Headers/$1.h" "https://github.com/SideStore/$1/releases/latest/download/$1.h"
            cp -v "$1.xcframework/ios-arm64/Headers/$1.h" "$1.xcframework/ios-arm64_x86_64-simulator/Headers/$1.h"
            echo
        else
            echo "Up-to-date"
        fi
        echo "$(date +%s),$LATEST_COMMIT" > ".last-prebuilt-fetch-$1"
    else
        echo "It hasn't been 6 hours and force was not specified, skipping update check"
    fi
}

check_for_update minimuxer "$1"
echo
check_for_update em_proxy "$1"
