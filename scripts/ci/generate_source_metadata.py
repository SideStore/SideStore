#!/usr/bin/env python3
import datetime
import hashlib
import json
import subprocess
from pathlib import Path
import argparse
import sys

SCRIPT_DIR = Path(__file__).resolve().parent


# ----------------------------------------------------------
# helpers
# ----------------------------------------------------------

def resolve_script(name: str) -> Path:
    p = Path.cwd() / name
    if p.exists():
        return p
    return SCRIPT_DIR / name


def sh(cmd: str, cwd: Path) -> str:
    try:
        return subprocess.check_output(
            cmd,
            shell=True,
            cwd=cwd,
            stderr=subprocess.STDOUT,
        ).decode().strip()
    except subprocess.CalledProcessError as e:
        print(e.output.decode(), file=sys.stderr)
        raise SystemExit(f"Command failed: {cmd}")


def file_size(path: Path) -> int:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.stat().st_size


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


# ----------------------------------------------------------
# entry
# ----------------------------------------------------------

def main():
    p = argparse.ArgumentParser()

    p.add_argument("--repo-root", required=True)
    p.add_argument("--ipa", required=True)
    p.add_argument("--output-dir", required=True)

    p.add_argument(
        "--output-name",
        default="source_metadata.json",
    )

    p.add_argument("--release-notes-dir", required=True)

    p.add_argument("--release-tag", required=True)
    p.add_argument("--marketing-version", required=True)
    p.add_argument("--short-commit", required=True)
    p.add_argument("--release-channel", required=True)
    p.add_argument("--bundle-id", required=True)

    # optional
    p.add_argument("--last-successful-commit")

    p.add_argument("--is-beta", action="store_true")

    args = p.parse_args()

    repo_root = Path(args.repo_root).resolve()
    ipa_path = Path(args.ipa).resolve()
    out_dir = Path(args.output_dir).resolve()
    notes_dir = Path(args.release_notes_dir).resolve()

    if not repo_root.is_dir():
        raise SystemExit(f"Invalid repo root: {repo_root}")

    if not ipa_path.is_file():
        raise SystemExit(f"Invalid IPA path: {ipa_path}")

    notes_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    out_file = out_dir / args.output_name

    # ------------------------------------------------------
    # generate release notes
    # ------------------------------------------------------

    print("Generating release notes…")

    script = resolve_script("generate_release_notes.py")

    if args.last_successful_commit:
        gen_cmd = (
            f"python3 {script} "
            f"{args.last_successful_commit} {args.release_tag} "
            f'--output-dir "{notes_dir}"'
        )
    else:
        gen_cmd = (
            f"python3 {script} "
            f"{args.short_commit} {args.release_tag} "
            f'--output-dir "{notes_dir}"'
        )

    sh(gen_cmd, cwd=repo_root)

    # ------------------------------------------------------
    # retrieve release notes
    # ------------------------------------------------------

    notes = sh(
        (
            f"python3 {script} "
            f"--retrieve {args.release_tag} "
            f"--output-dir \"{notes_dir}\""
        ),
        cwd=repo_root,
    )

    # ------------------------------------------------------
    # compute metadata
    # ------------------------------------------------------

    now = datetime.datetime.now(datetime.timezone.utc)
    formatted = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    human = now.strftime("%c")

    localized_description = getFormattedLocalizedDescription(args.marketing_version, args.short_commit, human, notes)

    metadata = {
        "is_beta": bool(args.is_beta),
        "bundle_identifier": args.bundle_id,
        "version_ipa": args.marketing_version,
        "version_date": formatted,
        "release_channel": args.release_channel.lower(),
        "size": file_size(ipa_path),
        "sha256": sha256(ipa_path),
        "download_url": (
            "https://github.com/SideStore/SideStore/releases/download/"
            f"{args.release_tag}/SideStore.ipa"
        ),
        "localized_description": localized_description,
    }

    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)

    print(f"Wrote {out_file}")

def getFormattedLocalizedDescription(marketing_version, short_commit, human, notes):
    return f"""
This is release for:
  - version: "{marketing_version}"
  - revision: "{short_commit}"
  - timestamp: "{human}"

Release Notes:
{notes}
""".lstrip("\n")

if __name__ == "__main__":
    main()
