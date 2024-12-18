#!/usr/bin/env python3

import os
import json
import sys

# Set environment variables with default values
VERSION_IPA = os.getenv("VERSION_IPA", "0.0.0")
VERSION_DATE = os.getenv("VERSION_DATE", "2000-12-18T00:00:00Z")
BETA = os.getenv("BETA", "true").lower() == "true"  # Convert to boolean
COMMIT_ID = os.getenv("COMMIT_ID", "1234567")
SIZE = int(os.getenv("SIZE", "0"))  # Convert to integer
SHA256 = os.getenv("SHA256", "")
LOCALIZED_DESCRIPTION = os.getenv("LOCALIZED_DESCRIPTION", "Invalid Update")
DOWNLOAD_URL = os.getenv("DOWNLOAD_URL", "https://github.com/SideStore/SideStore/releases/download/0.0.0/SideStore.ipa")
BUNDLE_IDENTIFIER = os.getenv("BUNDLE_IDENTIFIER", "com.SideStore.SideStore")

# Check if input file is provided
if len(sys.argv) < 2:
    print("Usage: python3 update_apps.py <input_file>")
    sys.exit(1)

input_file = sys.argv[1]
print(f"Input File: {input_file}")

# Debugging the environment variables
print("Version:", VERSION_IPA)
print("Version Date:", VERSION_DATE)
print("Beta:", BETA)
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

# Process the JSON data
updated = False
for app in data.get("apps", []):
    if app.get("bundleIdentifier") == BUNDLE_IDENTIFIER:
        # Update app-level metadata
        app.update({
            "version": VERSION_IPA,
            "versionDate": VERSION_DATE,
            "beta": BETA,
            "commitID": COMMIT_ID,
            "size": SIZE,
            "sha256": SHA256,
            "localizedDescription": LOCALIZED_DESCRIPTION,
            "downloadURL": DOWNLOAD_URL,
        })
        
        # Process the versions array
        versions = app.get("versions", [])
        if not versions or not (versions[0].get("version") == VERSION_IPA and versions[0].get("beta") == BETA):
            # Prepend a new version if no matching version exists
            new_version = {
                "version": VERSION_IPA,
                "date": VERSION_DATE,
                "localizedDescription": LOCALIZED_DESCRIPTION,
                "downloadURL": DOWNLOAD_URL,
                "beta": BETA,
                "commitID": COMMIT_ID,
                "size": SIZE,
                "sha256": SHA256,
            }
            versions.insert(0, new_version)
        else:
            # Update the existing version object
            versions[0].update({
                "version": VERSION_IPA,
                "date": VERSION_DATE,
                "localizedDescription": LOCALIZED_DESCRIPTION,
                "downloadURL": DOWNLOAD_URL,
                "beta": BETA,
                "commitID": COMMIT_ID,
                "size": SIZE,
                "sha256": SHA256,
            })
        app["versions"] = versions
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
