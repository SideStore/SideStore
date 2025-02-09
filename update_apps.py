#!/usr/bin/env python3

import os
import json
import sys

# SIDESTORE_BUNDLE_ID = "com.SideStore.SideStore"

# Set environment variables with default values
VERSION_IPA = os.getenv("VERSION_IPA")
VERSION_DATE = os.getenv("VERSION_DATE")
IS_BETA = os.getenv("IS_BETA")
RELEASE_CHANNEL = os.getenv("RELEASE_CHANNEL")
SIZE = os.getenv("SIZE")
SHA256 = os.getenv("SHA256")
LOCALIZED_DESCRIPTION = os.getenv("LOCALIZED_DESCRIPTION")
DOWNLOAD_URL = os.getenv("DOWNLOAD_URL")
# BUNDLE_IDENTIFIER = os.getenv("BUNDLE_IDENTIFIER", SIDESTORE_BUNDLE_ID)
BUNDLE_IDENTIFIER = os.getenv("BUNDLE_IDENTIFIER")

# Uncomment to debug/test by simulating dummy input locally
# VERSION_IPA = os.getenv("VERSION_IPA", "0.0.0")
# VERSION_DATE = os.getenv("VERSION_DATE", "2000-12-18T00:00:00Z")
# IS_BETA = os.getenv("IS_BETA", True)
# RELEASE_CHANNEL = os.getenv("RELEASE_CHANNEL", "alpha")
# SIZE = int(os.getenv("SIZE", "0"))  # Convert to integer
# SHA256 = os.getenv("SHA256", "")
# LOCALIZED_DESCRIPTION = os.getenv("LOCALIZED_DESCRIPTION", "Invalid Update")
# DOWNLOAD_URL = os.getenv("DOWNLOAD_URL", "https://github.com/SideStore/SideStore/releases/download/0.0.0/SideStore.ipa")

# Check if input file is provided
if len(sys.argv) < 2:
    print("Usage: python3 update_apps.py <input_file>")
    sys.exit(1)

input_file = sys.argv[1]
print(f"Input File: {input_file}")

# Debugging the environment variables
print("  ====> Required parameter list <====")
print("Bundle Identifier:", BUNDLE_IDENTIFIER)
print("Version:", VERSION_IPA)
print("Version Date:", VERSION_DATE)
print("IsBeta:", IS_BETA)
print("ReleaseChannel:", RELEASE_CHANNEL)
print("Size:", SIZE)
print("Sha256:", SHA256)
print("Localized Description:", LOCALIZED_DESCRIPTION)
print("Download URL:", DOWNLOAD_URL)

if IS_BETA is None:
    print("Setting IS_BETA = False since no value was provided")
    IS_BETA = False

if str(IS_BETA).lower() in ["true", "1", "yes"]:
    IS_BETA = True

# Read the input JSON file
try:
    with open(input_file, "r") as file:
        data = json.load(file)
except Exception as e:
    print(f"Error reading the input file: {e}")
    sys.exit(1)

if (not BUNDLE_IDENTIFIER or 
    not VERSION_IPA or 
    not VERSION_DATE or 
    not RELEASE_CHANNEL or 
    not SIZE or 
    not SHA256 or 
    not LOCALIZED_DESCRIPTION or 
    not DOWNLOAD_URL):
    print("One or more required parameter(s) were not defined as environment variable(s)")
    sys.exit(1)

# Convert to integer
SIZE = int(SIZE)

# Process the JSON data
updated = False

# apps = data.get("apps", [])
# appsToUpdate = [app for app in apps if app.get("bundleIdentifier") == BUNDLE_IDENTIFIER]
# if len(appsToUpdate) == 0:
#     print("No app with the specified bundle identifier found.")
#     sys.exit(1)

# if len(appsToUpdate) > 1:
#     print(f"Multiple apps with same `bundleIdentifier` = ${BUNDLE_IDENTIFIER} are not allowed!")
#     sys.exit(1)

# app = appsToUpdate[0]
# # Update app-level metadata for store front page
# app.update({
#     "beta": IS_BETA,
# })

# versions = app.get("versions", [])

# versionIfExists = [version for version in versions if version == VERSION_IPA]
# if versionIfExists:     # current version is a duplicate, so reject it
#     print(f"`version` = ${VERSION_IPA} already exists!, new build cannot have an existing version, Aborting!")
#     sys.exit(1)

# # create an entry and keep ready
# new_version = {
#     "version": VERSION_IPA,
#     "date": VERSION_DATE,
#     "localizedDescription": LOCALIZED_DESCRIPTION,
#     "downloadURL": DOWNLOAD_URL,
#     "size": SIZE,
#     "sha256": SHA256,
# }

# if versions is []:
#     versions.append(new_version)
# else:
#     # versions.insert(0, new_version)     # insert at front
#     versions[0] = new_version             # replace top one


# make it lowecase
RELEASE_CHANNEL = RELEASE_CHANNEL.lower()

version = data.get("version", 1)
if int(version) < 2:
    print("Only v2 and above are supported for direct updates to sources.json on push")
    sys.exit(1)

for app in data.get("apps", []):
    if app.get("bundleIdentifier") == BUNDLE_IDENTIFIER:
        if RELEASE_CHANNEL == "stable" :
            # Update app-level metadata for store front page
            app.update({
                "version": VERSION_IPA,
                "versionDate": VERSION_DATE,
                "size": SIZE,
                "sha256": SHA256,
                "localizedDescription": LOCALIZED_DESCRIPTION,
                "downloadURL": DOWNLOAD_URL,
            })
        
        # Process the versions array
        channels = app.get("releaseChannels", [])
        if not channels:
            app["releaseChannels"] = channels

        # create an entry and keep ready
        new_version = {
            "version": VERSION_IPA,
            "date": VERSION_DATE,
            "localizedDescription": LOCALIZED_DESCRIPTION,
            "downloadURL": DOWNLOAD_URL,
            "size": SIZE,
            "sha256": SHA256,
        }
        
        tracks = [track for track in channels if track.get("track") == RELEASE_CHANNEL]
        if len(tracks) > 1:
            print(f"Multiple tracks with same `track` name = ${RELEASE_CHANNEL} are not allowed!")
            sys.exit(1)
            
        if not tracks:
            # there was no entries in this release channel so create one
            track = {
                "track": RELEASE_CHANNEL,
                "releases": [new_version]
            }
            channels.insert(0, track)
        else:
            track = tracks[0]   # first result is the selected track
            # Update the existing TOP version object entry
            track["releases"][0] = new_version

        updated = True
        break

if not updated:
    print("No app with the specified bundle identifier found.")
    sys.exit(1)

# Save the updated JSON to the input file
try:
    print("\nUpdated Sources File:\n")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    with open(input_file, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=2, ensure_ascii=False)
    print("JSON successfully updated.")
except Exception as e:
    print(f"Error writing to the file: {e}")
    sys.exit(1)
