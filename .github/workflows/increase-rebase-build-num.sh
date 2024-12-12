#!/usr/bin/env bash

# Ensure we are in root directory
cd "$(dirname "$0")/../.."

DATE=`date -u +'%Y.%m.%d'`
BUILD_NUM=1

write() {
    sed -e "/MARKETING_VERSION = .*/s/$/-rebase.$DATE.$BUILD_NUM+$(git rev-parse --short HEAD)/" -i '' Build.xcconfig
    echo "$DATE,$BUILD_NUM" > .rebase-build-num
}

if [ ! -f ".rebase-build-num" ]; then
    write
    exit 0
fi

LAST_DATE=`cat .rebase-build-num | perl -n -e '/([^,]*),([^ ]*)$/ && print $1'`
LAST_BUILD_NUM=`cat .rebase-build-num | perl -n -e '/([^,]*),([^ ]*)$/ && print $2'`

if [[ "$DATE" != "$LAST_DATE" ]]; then
    write
else
    BUILD_NUM=`expr $LAST_BUILD_NUM + 1`
    write
fi

