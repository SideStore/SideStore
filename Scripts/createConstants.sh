#/bin/bash -e
# Pull GIT version number to use for informational purposes

# Scripts invoked by Xcode don't read any of the usual shell configuration files
# doing it here manually. PATH=foo:$PATH also gets ignored by XCode. 'source' seems to work fine though

if [ -f "$HOME/.profile" ] ; then
    source "$HOME/.profile"
else
    echo "No $HOME/.profile exists. PATH may not find correct version of Git if installed outside of XCode; ie. MacPorts or other build systems."
fi

if [ -f "$HOME/.bash_profile" ] ; then
    source "$HOME/.bash_profile"
else
    echo "No $HOME/.bash_profile exists. PATH may not find correct version of Git if installed outside of XCode; ie. MacPorts or other build systems."
fi

PLISTBUDDY=/usr/libexec/PlistBuddy
NOW=`date`
INFOPATH="${PROJECT_DIR}/${INFOPLIST_FILE}"

###### ------------ SVN VERSION -------------------
#SVNBIN=svn
#SVNVERSIONBIN=svnversion
#
# if [ "command -v $SVNVERSIONBIN" ] ; then
#     svnrevision=`$SVNVERSIONBIN -nc ${PROJECT_DIR}| /usr/bin/sed -e 's/^[^:]*://'`
#     svnrevisionnoflags=`$SVNVERSIONBIN -nc ${PROJECT_DIR}| /usr/bin/sed -e 's/^[^:]*://;s/[A-Za-z]//'`
# else
#     echo "$SVNVERSIONBIN not found."
# fi

# if [ "command -v $SVNBIN" ] ; then
#     svndate=`LC_ALL=C $SVNBIN info ${PROJECT_DIR}| awk '/^Last Changed Date:/ {print $4,$5}'`
# else
#     echo "$SVNBIN not found."
# fi

# if [ "command -v $PLISTBUDDY" ] ; then
#     ## Read the app version (x.y.z) from the PList
#     appversion=$($PLISTBUDDY -c "Print :CFBundleShortVersionString" "${INFOPATH}")

#     ## Set the build version as the SVN revision
#     /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${svnrevisionnoflags}" ${INFOPATH}
# else
#     echo "$PLISTBUDDY not found."
# fi

plist_buddy_installed() {
  [-x "$(command -v "$PLISTBUDDY")"]
}

if [[ plist_buddy_installed && "${INFOPATH}" == *".plist"*  ]]; then
    if [ -f "${INFOPATH}" ]; then
        ## Read the app version (x.y.z) from the PList
        appversion=$($PLISTBUDDY -c "Print :CFBundleShortVersionString" "${INFOPATH}")
        echo "appversion=${appversion}"

        BUILT_INFO_PATH="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
        if [ -f "${BUILT_INFO_PATH}" ]; then
          PLIST_GIT_COMMIT_COUNT=$($PLISTBUDDY -c "Print :CFBundleVersion" "${BUILT_INFO_PATH}")
          echo "Plist version is $PLIST_GIT_COMMIT_COUNT"
        else
          PLIST_GIT_COMMIT_COUNT="0"
        fi
#        if [ "$x" = "Debug" ]; then
#          appversion=$($PLISTBUDDY -c "Print :CFBundleShortVersionString" "${INFOPATH}")
#        fi
    else
        error_exit "${INFOPATH} not found"
    fi
fi

error_exit()
{
    echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

success_exit()
{
    echo "${PROGNAME}: ${1:-"Completed"}" 1>&2
    exit 0
}

VERSION_H_PATH="${PROJECT_DIR}/Constants/Constants.h"
VERSION_SWIFT_PATH="${PROJECT_DIR}/Constants/Constants.swift"

######## --------------- GIT VERISON -------------------
GIT=`xcrun -find git`
if [ "command -v '$GIT'" ] ; then
    GIT_COMMIT_COUNT_RAW=`"${GIT}" rev-list --count HEAD`
    GIT_TAG=`"${GIT}" describe --tags --always --dirty`
    GIT_DATE=`"${GIT}" log -1 --format="%cd" --date="local"`
    GIT_BRANCH=`"${GIT}" branch | grep \* | cut -d ' ' -f2-`
    # Use this to bump the number by X
    GIT_COMMIT_COUNT=$(($GIT_COMMIT_COUNT_RAW+0))
    echo "Commit count is $GIT_COMMIT_COUNT"
else
    error_exit "$LINENO: $GIT not found."
fi

if [ "$GIT_COMMIT_COUNT" == "$PLIST_GIT_COMMIT_COUNT" ]; then
  success_exit "GIT commit count hasn't changed. No need to update files."
fi

vpath="$SRCROOT/.version"
echo "Testing for ${vpath}"
if [[ -f $VERSION_H_PATH ]] && [[ -f $VERSION_SWIFT_PATH ]] && [[ -f $vpath ]] && [[ "$(< ${vpath})" == "${GIT_DATE}" ]]; then
  success_exit "${vpath} matches ${GIT_DATE}"
else
  echo "$GIT_DATE" > "${vpath}"
fi

echo "Creating Constants.h in" ${PROJECT_DIR}

cat <<EOF > "${VERSION_H_PATH}"

// Do not edit!  This file was autogenerated
//      by $0
//      on $NOW
//      user $VERSION_INFO_BUILDER
//      for build target ${TARGET_NAME}
//
// gitrevision and gitdate are as reported by git at that point in time,
// compiledate and compiletime are being filled gcc at compilation

#include <stdlib.h>

static NSString* const kAppVersion              = @"${appversion}";
static NSString* const kGITRevisionNumber       = @"${GIT_COMMIT_COUNT}";
static NSString* const kGITTag                  = @"${GIT_TAG}";
static NSString* const kGITDate                 = @"${GIT_DATE}";
static NSString* const kGITBranch               = @"${GIT_BRANCH}";
static NSString* const kAppBuildConfiguration   = @"${CONFIGURATION}";
static NSString* const kOrgIdentifier           = @"${ORG_IDENTIFIER}";
static NSString* const kOrgPrefix               = @"${ORG_PREFIX}";
static NSString* const kProductBundleIdentifier = @"${PRODUCT_BUNDLE_IDENTIFIER}";
static NSString* const kAppGroupIdentifier      = @"${APP_GROUP_IDENTIFIER}";
static NSString* const kiCloudContainerIdenfitier = @"${ICLOUD_CONTAINER_IDENTIFIER}";
static NSString* const kUbiquityIdentityTokenKey  = @"${PRODUCT_BUNDLE_IDENTIFIER}.UbiquityIdentityToken";

// Suppress warnings incase you choose not to use these variables
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused"

static const char* gitrevision          = "${GIT_COMMIT_COUNT}";
static const char* gittag               = "${GIT_TAG}";
static const char* gitdate              = "${GIT_DATE}";
static const char* gitbranch            = "${GIT_BRANCH}";
static const char* appversion           = "${appversion}";
static const char* buildconfiguration   = "${CONFIGURATION}";
static const char* builtByUser          = "${USER}";
static const char* OrgIdentifier           = "${ORG_IDENTIFIER}";
static const char* OrgPrefix               = "${ORG_PREFIX}";
static const char* ProductBundleIdentifier = "${PRODUCT_BUNDLE_IDENTIFIER}";
static const char* AppGroupIdentifier      = "${APP_GROUP_IDENTIFIER}";
static const char* iCloudContainerIdenfitier = "${ICLOUD_CONTAINER_IDENTIFIER}";
static const char* UbiquityIdentityTokenKey     = "${PRODUCT_BUNDLE_IDENTIFIER}.UbiquityIdentityToken";


// static const char* compiletime          = __TIME__;
// static const char* compiledate          = __DATE__;

#pragma GCC diagnostic pop

// Diagnostic info
/*
    Info.plist path:${INFOPATH}
    PWD : ${PWD}
    XCode version ${XCODE_PRODUCT_BUILD_VERSION}
    PATH : ${PATH}
*/
EOF

echo "Creating Constants.swift in" ${PROJECT_DIR}

cat <<EOF > "${VERSION_SWIFT_PATH}"
// Do not edit!  This file was autogenerated
//      by $0
//      on $NOW
//      user $VERSION_INFO_BUILDER
//      for build target ${TARGET_NAME}
//
// gitrevision and gitdate are as reported by git at that point in time,
// compiledate and compiletime are being filled gcc at compilation

public enum Constants {
  public static var kAppVersion : String = "${appversion}"
  public static var kGITRevisionNumber : String = "${GIT_COMMIT_COUNT}"
  public static var kGITTag : String = "${GIT_TAG}"
  public static var kGITDate : String = "${GIT_DATE}"
  public static var kGITBranch : String = "${GIT_BRANCH}"
  public static var kAppBuildConfiguration : String  = "${CONFIGURATION}"

  public static var gitrevision          = "${GIT_COMMIT_COUNT}"
  public static var gittag               = "${GIT_TAG}"
  public static var gitdate              = "${GIT_DATE}"
  public static var gitbranch            = "${GIT_BRANCH}"
  public static var appversion           = "${appversion}"
  public static var buildconfiguration   = "${CONFIGURATION}"
  public static var builtByUser          = "${USER}"
  public static var kOrgIdentifier               = "${ORG_IDENTIFIER}"
  public static var kOrgPrefix                   = "${ORG_PREFIX}"
  public static var kProductBundleIdentifier     = "${PRODUCT_BUNDLE_IDENTIFIER}"
  public static var kAppGroupIdentifier          = "${APP_GROUP_IDENTIFIER}"
  public static var kiCloudContainerIdenfitier   = "${ICLOUD_CONTAINER_IDENTIFIER}"
  public static var kUbiquityIdentityTokenKey     = "${PRODUCT_BUNDLE_IDENTIFIER}.UbiquityIdentityToken"

  public static var kPatreonURL     = "${PATREON_URL}"
  public static var kSupportEMAIL     = "${SUPPORT_EMAIL}"
}
// public let compiletime          = __TIME__
// public let compiledate          = __DATE__

// Diagnostic info
/*
    Info.plist path:${INFOPATH}
    PWD : ${PWD}
    XCode version ${XCODE_PRODUCT_BUILD_VERSION}
    PATH : ${PATH}
*/
EOF
##
#echo "$REV2" > ${PROJECT_DIR}/SvnRevision.txt
