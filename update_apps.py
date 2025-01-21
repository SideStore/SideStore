#!/usr/bin/env python3

import os
import json
import sys

SIDESTORE_BUNDLE_ID = "com.SideStore.SideStore"

# Set environment variables with default values
VERSION_IPA = os.getenv("VERSION_IPA")
VERSION_DATE = os.getenv("VERSION_DATE")
RELEASE_CHANNEL = os.getenv("RELEASE_CHANNEL")
COMMIT_ID = os.getenv("COMMIT_ID")
SIZE = os.getenv("SIZE")
SHA256 = os.getenv("SHA256")
LOCALIZED_DESCRIPTION = os.getenv("LOCALIZED_DESCRIPTION")
DOWNLOAD_URL = os.getenv("DOWNLOAD_URL")
BUNDLE_IDENTIFIER = os.getenv("BUNDLE_IDENTIFIER", SIDESTORE_BUNDLE_ID)

# Uncomment to debug/test by simulating dummy input locally
# VERSION_IPA = os.getenv("VERSION_IPA", "0.0.0")
# VERSION_DATE = os.getenv("VERSION_DATE", "2000-12-18T00:00:00Z")
# RELEASE_CHANNEL = os.getenv("RELEASE_CHANNEL", "alpha")
# COMMIT_ID = os.getenv("COMMIT_ID", "1234567")
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
print("Version:", VERSION_IPA)
print("Version Date:", VERSION_DATE)
print("ReleaseChannel:", RELEASE_CHANNEL)
print("Commit ID:", COMMIT_ID)
print("Size:", SIZE)
print("Sha256:", SHA256)
print("Localized Description:", LOCALIZED_DESCRIPTION)
print("Download URL:", DOWNLOAD_URL)

# Read the input JSON file
try:
    with open(input_file, "r") as file:
        data = json.load(file)
except Exception as e:
    print(f"Error reading the input file: {e}")
    sys.exit(1)

if (VERSION_IPA == None or \
    VERSION_DATE == None or \
    RELEASE_CHANNEL == None or \
    SIZE == None or \
    SHA256 == None or \
    LOCALIZED_DESCRIPTION == None or \
    DOWNLOAD_URL == None):
    print("One or more required parameter(s) were not defined as environment variable(s)")
    sys.exit(1)

# make it lowecase
RELEASE_CHANNEL = RELEASE_CHANNEL.lower()
# Convert to integer
SIZE = int(SIZE)

if RELEASE_CHANNEL != 'stable' and COMMIT_ID is None:
    print("Commit ID cannot be empty when ReleaseChannel is not 'stable' ")
    sys.exit(1)

version = data.get("version")
if int(version) < 2:
    print("Only v2 and above are supported for direct updates to sources.json on push")
    sys.exit(1)

# Process the JSON data
updated = False
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
        channels = app.get("releaseChannels", {})
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
        # add commit ID if release is not stable 
        if RELEASE_CHANNEL != 'stable':
            new_version["commitID"] = COMMIT_ID

        if not channels.get(RELEASE_CHANNEL):
            # there was no entries in this release channel so create one
            channels[RELEASE_CHANNEL] = [new_version]
        else:
            # Update the existing TOP version object entry
            channels[RELEASE_CHANNEL][0] = new_version

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
