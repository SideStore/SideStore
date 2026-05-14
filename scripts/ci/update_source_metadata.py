#!/usr/bin/env python3

import json
import sys
from pathlib import Path


# ----------------------------------------------------------
# metadata
# ----------------------------------------------------------

def load_metadata(metadata_file: Path):
    if not metadata_file.exists():
        raise SystemExit(f"Missing metadata file: {metadata_file}")

    with open(metadata_file, "r", encoding="utf-8") as f:
        meta = json.load(f)

    print("  ====> Required parameter list <====")
    for k, v in meta.items():
        print(f"{k}: {v}")

    required = [
        "bundle_identifier",
        "version_ipa",
        "version_date",
        "release_channel",
        "size",
        "sha256",
        "localized_description",
        "download_url",
    ]

    for r in required:
        if not meta.get(r):
            raise SystemExit("One or more required metadata fields missing")

    meta["size"] = int(meta["size"])
    meta["release_channel"] = meta["release_channel"].lower()

    return meta


# ----------------------------------------------------------
# source loading
# ----------------------------------------------------------

def load_source(source_file: Path):
    if source_file.exists():
        with open(source_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        print("source.json missing — creating minimal structure")
        data = {"version": 2, "apps": []}

    if int(data.get("version", 1)) < 2:
        raise SystemExit("Only v2 and above are supported")

    return data


# ----------------------------------------------------------
# locate app
# ----------------------------------------------------------

def ensure_app(data, bundle_id):
    apps = data.setdefault("apps", [])

    app = next(
        (a for a in apps if a.get("bundleIdentifier") == bundle_id),
        None,
    )

    if app is None:
        print("App entry missing — creating new app entry")
        app = {
            "bundleIdentifier": bundle_id,
            "releaseChannels": [],
        }
        apps.append(app)

    return app


# ----------------------------------------------------------
# update storefront
# ----------------------------------------------------------

def update_storefront_if_needed(app, meta):
    if meta["release_channel"] == "stable":
        app.update({
            "version": meta["version_ipa"],
            "versionDate": meta["version_date"],
            "size": meta["size"],
            "sha256": meta["sha256"],
            "localizedDescription": meta["localized_description"],
            "downloadURL": meta["download_url"],
        })


# ----------------------------------------------------------
# update release channel (ORIGINAL FORMAT)
# ----------------------------------------------------------

def update_release_channel(app, meta):
    channels = app.setdefault("releaseChannels", [])

    new_version = {
        "version": meta["version_ipa"],
        "date": meta["version_date"],
        "localizedDescription": meta["localized_description"],
        "downloadURL": meta["download_url"],
        "size": meta["size"],
        "sha256": meta["sha256"],
    }

    tracks = [
        t for t in channels
        if isinstance(t, dict)
        and t.get("track") == meta["release_channel"]
    ]

    if len(tracks) > 1:
        raise SystemExit(f"Multiple tracks named {meta['release_channel']}")

    if not tracks:
        channels.insert(0, {
            "track": meta["release_channel"],
            "releases": [new_version],
        })
    else:
        track = tracks[0]
        releases = track.setdefault("releases", [])

        if not releases:
            releases.append(new_version)
        else:
            releases[0] = new_version


# ----------------------------------------------------------
# save
# ----------------------------------------------------------

def save_source(source_file: Path, data):
    print("\nUpdated Sources File:\n")
    print(json.dumps(data, indent=2, ensure_ascii=False))

    source_file.parent.mkdir(parents=True, exist_ok=True)

    with open(source_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print("JSON successfully updated.")


# ----------------------------------------------------------
# main
# ----------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 update_apps.py <metadata.json> <source.json>")
        sys.exit(1)

    metadata_file = Path(sys.argv[1])
    source_file = Path(sys.argv[2])

    meta = load_metadata(metadata_file)
    data = load_source(source_file)

    app = ensure_app(data, meta["bundle_identifier"])

    update_storefront_if_needed(app, meta)
    update_release_channel(app, meta)

    save_source(source_file, data)


if __name__ == "__main__":
    main()