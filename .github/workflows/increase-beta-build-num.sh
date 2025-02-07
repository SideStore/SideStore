#!/usr/bin/env bash

# Ensure we are in root directory
cd "$(dirname "$0")/../.."

DATE=`date -u +'%Y.%m.%d'`
BUILD_NUM=1

# Use RELEASE_CHANNEL from the environment variable or default to "beta"
RELEASE_CHANNEL=${RELEASE_CHANNEL:-"beta"}

write() {
    sed -e "/MARKETING_VERSION = .*/s/$/-$RELEASE_CHANNEL.$DATE.$BUILD_NUM+$(git rev-parse --short HEAD)/" -i '' Build.xcconfig
    echo "$DATE,$BUILD_NUM" > build_number.txt
}

if [ ! -f "build_number.txt" ]; then
    write
    exit 0
fi

LAST_DATE=`cat build_number.txt | perl -n -e '/([^,]*),([^ ]*)$/ && print $1'`
LAST_BUILD_NUM=`cat build_number.txt | perl -n -e '/([^,]*),([^ ]*)$/ && print $2'`

# if [[ "$DATE" != "$LAST_DATE" ]]; then
#     write
# else
#     BUILD_NUM=`expr $LAST_BUILD_NUM + 1`
#     write
# fi

# Build number is always incremental
BUILD_NUM=`expr $LAST_BUILD_NUM + 1`
write
