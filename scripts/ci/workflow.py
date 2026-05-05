#!/usr/bin/env python3
import os
import sys
import subprocess
import datetime
from pathlib import Path
import time
import json
import re
from posix import getcwd

# REPO ROOT relative to script dir
ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'scripts/ci'
BUILD_SETTINGS_OUTFILE = "project-build-settings.txt"

# ----------------------------------------------------------
# helpers
# ----------------------------------------------------------

def run(cmd, check=True, cwd=None):
    wd = cwd if cwd is not None else ROOT
    print(f"$ {cmd}", flush=True, file=sys.stderr)
    subprocess.run(
        cmd,
        shell=True,
        cwd=wd,
        check=check,
        stdout=sys.stderr,
        stderr=sys.stderr,
    )
    print("", flush=True, file=sys.stderr)

def runAndGet(cmd, cwd=None):
    wd = cwd if cwd is not None else ROOT
    print(f"$ {cmd}", flush=True, file=sys.stderr)
    result = subprocess.run(
        cmd,
        shell=True,
        cwd=wd,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        check=True,
    )
    out = result.stdout.strip()
    print(out, flush=True, file=sys.stderr)
    print("", flush=True, file=sys.stderr)
    return out

def getenv(name, default=""):
    return os.environ.get(name, default)

# ----------------------------------------------------------
# SHARED
# ----------------------------------------------------------

def short_commit():
    return runAndGet("git rev-parse --short HEAD")

def count_new_commits(last_commit):
    if not last_commit or not last_commit.strip():
        return 0

    try:
        total = int(runAndGet("git rev-list --count HEAD"))
        if total == 1:
            head = runAndGet("git rev-parse HEAD")
            return 1 if head != last_commit else 0

        out = runAndGet(f"git rev-list --count {last_commit}..HEAD")
        return int(out)
    except Exception:
        return 0

# ----------------------------------------------------------
# PROJECT INFO
# ----------------------------------------------------------
def dump_project_settings(outdir=None):
    outfile = Path(outdir).resolve() / BUILD_SETTINGS_OUTFILE if outdir else BUILD_SETTINGS_OUTFILE
    run(f"xcodebuild -showBuildSettings 2>&1 > '{outfile}'")

def _extract_setting(cmd):
    out = runAndGet(cmd + " || true").strip()   # prevent grep failure from aborting
    return out if out else None

def _read_dumped_build_setting(name):
    return _extract_setting(
        f"cat '{BUILD_SETTINGS_OUTFILE}' "
        f"| grep '{name} = ' "
        "| tail -1 "
        "| sed -e 's/.*= //g'"
    )

def query_build_setting(name):
    return _extract_setting(
        f"xcodebuild -showBuildSettings 2>&1 "
        f"| grep '{name} = ' "
        "| tail -1 "
        "| sed -e 's/.*= //g'"
    )

def get_product_name():  return query_build_setting("PRODUCT_NAME")
def get_bundle_id():     return query_build_setting("PRODUCT_BUNDLE_IDENTIFIER")
def read_product_name(): return _read_dumped_build_setting("PRODUCT_NAME")
def read_bundle_id():    return _read_dumped_build_setting("PRODUCT_BUNDLE_IDENTIFIER")

def get_marketing_version():
    return runAndGet(f"grep MARKETING_VERSION {ROOT}/Build.xcconfig | sed -e 's/MARKETING_VERSION = //g'")

def set_marketing_version(version):
    run(
        f"sed -E -i '' "
        f"'s/^MARKETING_VERSION = .*/MARKETING_VERSION = {version}/' "
        f"{ROOT}/Build.xcconfig"
    )


def compute_normalized_version(marketing, build_num, short):
    now = datetime.datetime.now(datetime.UTC)
    date = now.strftime("%Y%m%d")   # normalized date
    base = marketing.strip()
    return f"{base}-{date}.{build_num}+{short}"

# ----------------------------------------------------------
# CLEAN
# ----------------------------------------------------------

def clean():
    run("make clean")

def clean_derived_data():
    run("rm -rf ~/Library/Developer/Xcode/DerivedData/*", check=False)

def clean_spm_cache():
    run("rm -rf ~/Library/Caches/org.swift.swiftpm/*", check=False)

# ----------------------------------------------------------
# BUILD
# ----------------------------------------------------------

def build():
    run("mkdir -p build/logs")
    run(
        "set -o pipefail && "
        "NSUnbufferedIO=YES make -B build "
        "2>&1 | tee -a build/logs/build.log | xcbeautify --renderer github-actions"
    )
    run("make fakesign | tee -a build/logs/build.log")
    run("make ipa | tee -a build/logs/build.log")
    run("zip -r -9 ./SideStore.dSYMs.zip ./SideStore.xcarchive/dSYMs")

# ----------------------------------------------------------
# TESTS BUILD
# ----------------------------------------------------------

def tests_build():
    run("mkdir -p build/logs")
    run(
        "NSUnbufferedIO=YES make -B build-tests "
        "2>&1 | tee -a build/logs/tests-build.log | xcbeautify --renderer github-actions"
    )

# ----------------------------------------------------------
# TESTS RUN
# ----------------------------------------------------------

def is_sim_booted(model):
    out = runAndGet(f'xcrun simctl list devices "{model}"')
    return "Booted" in out

def boot_sim_async(model):
    log = ROOT / "build/logs/tests-run.log"
    log.parent.mkdir(parents=True, exist_ok=True)

    if is_sim_booted(model):
        run(f'echo "Simulator {model} already booted." | tee -a {log}')
        return

    run(f'echo "Booting simulator {model} asynchronously..." | tee -a {log}')

    with open(log, "a") as f:
        subprocess.Popen(
            ["xcrun", "simctl", "boot", model],
            cwd=ROOT,
            stdout=f,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

def boot_sim_sync(model):
    run("mkdir -p build/logs")

    for i in range(1, 7):
        if is_sim_booted(model):
            run('echo "Simulator booted." | tee -a build/logs/tests-run.log')
            return

        run(f'echo "Simulator not ready (attempt {i}/6), retrying in 10s..." | tee -a build/logs/tests-run.log')
        time.sleep(10)

    raise SystemExit("Simulator failed to boot")

def tests_run(model):
    run("mkdir -p build/logs")

    if not is_sim_booted(model):
        boot_sim_sync(model)

    run("make run-tests 2>&1 | tee -a build/logs/tests-run.log")
    run("zip -r -9 ./test-results.zip ./build/tests")

# ----------------------------------------------------------
# LOG ENCRYPTION
# ----------------------------------------------------------

def encrypt_logs(name):
    pwd = getenv("BUILD_LOG_ZIP_PASSWORD")
    cwd = getcwd()
    if not pwd or not pwd.strip():
        print("BUILD_LOG_ZIP_PASSWORD not set — logs will be uploaded UNENCRYPTED", file=sys.stderr)
        run(f'cd {cwd}/build/logs && zip -r {cwd}/{name}.zip *')
        return
    run(f'cd {cwd}/build/logs && zip -e -P "{pwd}" {cwd}/{name}.zip *')

# ----------------------------------------------------------
# RELEASE NOTES
# ----------------------------------------------------------

def release_notes(tag):
    run(
        f"python3 {SCRIPTS}/generate_release_notes.py "
        f"{tag} "
        f"--repo-root {ROOT} "
        f"--output-dir {ROOT}"
    )

def retrieve_release_notes(tag):
    return runAndGet(
        f"python3 {SCRIPTS}/generate_release_notes.py "
        f"--retrieve {tag} "
        f"--output-dir {ROOT}"
    )

# ----------------------------------------------------------
# DEPLOY SOURCE.JSON
# ----------------------------------------------------------
def generate_metadata(release_tag, short_commit, marketing_version, channel, bundle_id, ipa_name, last_successful_commit=None):
    ipa_path = ROOT / ipa_name
    metadata = 'source-metadata.json'

    if not ipa_path.exists():
        raise SystemExit(f"{ipa_path} missing")

    cmd = (
        f"python3 {SCRIPTS}/generate_source_metadata.py "
        f"--repo-root {ROOT} "
        f"--ipa {ipa_path} "
        f"--output-dir {ROOT} "
        f"--output-name {metadata} "
        f"--release-notes-dir {ROOT} "
        f"--release-tag {release_tag} "
        f"--marketing-version {marketing_version} "
        f"--short-commit {short_commit} "
        f"--release-channel {channel} "
        f"--bundle-id {bundle_id}"
    )

    if last_successful_commit:
        cmd += f" --last-successful-commit {last_successful_commit}"

    run(cmd)

def deploy(repo, source_json, release_tag, marketing_version):
    repo = (ROOT / repo).resolve()
    source_json_path = repo / source_json
    metadata = 'source-metadata.json'

    if not repo.exists():
        raise SystemExit(f"{repo} repo missing")

    if not (repo / ".git").exists():
        print("Repo is not a git repository, skipping deploy", file=sys.stderr)
        return

    if not source_json_path.exists():
        raise SystemExit(f"{source_json} missing inside repo")

    run("git config user.name 'GitHub Actions'", check=False)
    run("git config user.email 'github-actions@github.com'", check=False)

    # ------------------------------------------------------
    run("git fetch origin main", check=False, cwd=repo)
    run("git switch main || git switch -c main origin/main", cwd=repo)
    run("git reset --hard origin/main", cwd=repo)
    # ------------------------------------------------------

    max_attempts = 5
    for attempt in range(1, max_attempts + 1):
        if attempt > 1:
            run("git fetch --depth=1 origin HEAD", check=False, cwd=repo)
            run("git reset --hard FETCH_HEAD", check=False, cwd=repo)

        # regenerate after reset so we don't lose changes
        run(f"python3 {SCRIPTS}/update_source_metadata.py '{ROOT}/{metadata}' '{source_json_path}'", cwd=repo)
        run(f"git add --verbose {source_json}", cwd=repo)
        run(f"git commit -m '{release_tag} - deployed {marketing_version}' || true", cwd=repo)

        rc = subprocess.call("git push", shell=True, cwd=repo)

        if rc == 0:
            print("Deploy push succeeded", file=sys.stderr)
            break

        print(f"Push rejected (attempt {attempt}/{max_attempts}), retrying...", file=sys.stderr)
        time.sleep(0.5)
    else:
        raise SystemExit("Deploy push failed after retries")


def last_successful_commit(is_stable, tag=None):
    is_stable = str(is_stable).lower() in ("1", "true", "yes")

    try:
        if is_stable:
            prev_tag = runAndGet(
                r'git tag --sort=-v:refname '
                r'| grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" '
                r'| sed -n "2p" || true'
            ).strip()

            if prev_tag:
                return runAndGet(f'git rev-parse "{prev_tag}^{{commit}}"')

            return None   # ← changed

        if tag:
            exists = subprocess.call(
                f'git rev-parse -q --verify "refs/tags/{tag}"',
                shell=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ) == 0

            if exists:
                return runAndGet(f'git rev-parse "{tag}^{{commit}}"')

    except Exception:
        pass

    return None

def upload_release(release_name, release_tag, commit_sha, repo, upstream_tag_recommended, is_stable=False):
    is_stable = str(is_stable).lower() in ("1", "true", "yes")
    draft = False
    prerelease = True
    latest = False

    if is_stable:
        prerelease = False
        latest = True

    token = getenv("GH_TOKEN")
    if token:
        os.environ["GH_TOKEN"] = token

    metadata_path = ROOT / "source-metadata.json"

    if not metadata_path.exists():
        raise SystemExit("source-metadata.json missing")

    meta = json.loads(metadata_path.read_text())

    marketing_version = meta.get("version_ipa")
    build_datetime = meta.get("version_date")

    dt = datetime.datetime.fromisoformat(
        build_datetime.replace("Z", "+00:00")
    )
    built_time = dt.strftime("%a %b %d %H:%M:%S %Y")
    built_date = dt.strftime("%Y-%m-%d")

    release_notes = runAndGet(
        f"python3 {SCRIPTS}/generate_release_notes.py "
        f"--retrieve {release_tag} "
        f"--output-dir {ROOT}"
    )

    if is_stable:
        release_notes = re.sub(
            r'(?im)^[ \t]*#{1,6}[ \t]*what[’\']?s[ \t]+changed[ \t]*$',
            "## What's Changed",
            release_notes,
            flags=re.IGNORECASE | re.MULTILINE,
        )

    upstream_block = ""
    if upstream_tag_recommended and upstream_tag_recommended.strip():
        tag = upstream_tag_recommended.strip()
        upstream_block = (
            f"If you want to try out new features early but want a lower chance of bugs, "
            f"you can look at [{repo} {tag}]"
            f"(https://github.com/{repo}/releases?q={tag}).\n\n"
        )

    header = getFormattedUploadMsg(
        release_name, commit_sha, repo, upstream_block,
        built_time, built_date, marketing_version, is_stable,
    )

    body = header + release_notes.lstrip() + "\n"

    body_file = ROOT / "release_body.md"
    body_file.write_text(body, encoding="utf-8")

    draft_flag = "--draft" if draft else ""
    prerelease_flag = "--prerelease" if prerelease else ""
    latest_flag = "--latest=true" if latest else ""

    # create release if it doesn't exist
    exists = subprocess.call(
        f'gh release view "{release_tag}"',
        shell=True,
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ) == 0

    if exists:
        run(
            f'gh release edit "{release_tag}" '
            f'--title "{release_name}" '
            f'--notes-file "{body_file}" '
            f'{draft_flag} {prerelease_flag} {latest_flag}'
        )
    else:
        run(
            f'gh release create "{release_tag}" '
            f'--title "{release_name}" '
            f'--notes-file "{body_file}" '
            f'{draft_flag} {prerelease_flag} {latest_flag}'
        )

    run(
        f'gh release upload "{release_tag}" '
        f'SideStore.ipa SideStore.dSYMs.zip build-logs.zip '
        f'--clobber'
    )

    run(f'git tag -f "{release_tag}" "{commit_sha}"')
    run(f'git push origin "refs/tags/{release_tag}" --force')


def getFormattedUploadMsg(release_name, commit_sha, repo, upstream_block, built_time, built_date, marketing_version, is_stable):
    experimental_header = ""
    if not is_stable:
        experimental_header = f"""
This is an ⚠️ **EXPERIMENTAL** ⚠️ {release_name} build for commit [{commit_sha}](https://github.com/{repo}/commit/{commit_sha}).

{release_name} builds are **extremely experimental builds only meant to be used by developers and beta testers. They often contain bugs and experimental features. Use at your own risk!**

""".lstrip("\n")

    header = f"""
{experimental_header}{upstream_block}## Build Info

Built at (UTC): `{built_time}`
Built at (UTC date): `{built_date}`
Commit SHA: `{commit_sha}`
Version: `{marketing_version}`
""".lstrip("\n")
    return header

# ----------------------------------------------------------
# ENTRYPOINT
# ----------------------------------------------------------

COMMANDS = {
    # ----------------------------------------------------------
    # SHARED
    # ----------------------------------------------------------
    "commit-id"               : (short_commit,              0, ""),
    "count-new-commits"       : (count_new_commits,         1, "<last_successful_commit>"),

    # ----------------------------------------------------------
    # PROJECT INFO
    # ----------------------------------------------------------
    "get-marketing-version"   : (get_marketing_version,     0, ""),
    "set-marketing-version"   : (set_marketing_version,     1, "<normalized_version>"),
    "compute-normalized"      : (compute_normalized_version,3, "<marketing> <build_num> <short_commit>"),
    "get-product-name"        : (get_product_name,          0, ""),
    "get-bundle-id"           : (get_bundle_id,             0, ""),
    "dump-project-settings"   : (dump_project_settings,     0, ""),
    "read-product-name"       : (read_product_name,         0, ""),
    "read-bundle-id"          : (read_bundle_id,            0, ""),

    # ----------------------------------------------------------
    # CLEAN
    # ----------------------------------------------------------
    "clean"                   : (clean,                     0, ""),
    "clean-derived-data"      : (clean_derived_data,        0, ""),
    "clean-spm-cache"         : (clean_spm_cache,           0, ""),

    # ----------------------------------------------------------
    # BUILD
    # ----------------------------------------------------------
    "build"                   : (build,                     0, ""),

    # ----------------------------------------------------------
    # TESTS
    # ----------------------------------------------------------
    "tests-build"             : (tests_build,               0, ""),
    "tests-run"               : (tests_run,                 1, "<model>"),
    "boot-sim-async"          : (boot_sim_async,            1, "<model>"),
    "boot-sim-sync"           : (boot_sim_sync,             1, "<model>"),

    # ----------------------------------------------------------
    # LOG ENCRYPTION
    # ----------------------------------------------------------
    "encrypt-build"           : (lambda: encrypt_logs("build-logs"),        0, ""),
    "encrypt-tests-build"     : (lambda: encrypt_logs("tests-build-logs"),  0, ""),
    "encrypt-tests-run"       : (lambda: encrypt_logs("tests-run-logs"),    0, ""),

    # ----------------------------------------------------------
    # RELEASE / DEPLOY
    # ----------------------------------------------------------
    "last-successful-commit"  : (last_successful_commit,     1, "<is_stable> [tag]"),
    "release-notes"           : (release_notes,              1, "<tag>"),
    "retrieve-release-notes"  : (retrieve_release_notes,     1, "<tag>"),
    "generate-metadata"       : (generate_metadata,          7,
                                 "<release_tag> <short_commit> <marketing_version> <channel> <bundle_id> <ipa_name> [last_successful_commit]"),
    "deploy"                  : (deploy,                     4,
                                 "<repo> <source_json> <release_tag> <marketing_version>"),
    "upload-release"          : (upload_release,             5,
                                 "<release_name> <release_tag> <commit_sha> <repo> <upstream_tag_recommended> [is_stable]"),}

def main():
    def usage():
        lines = ["Available commands:"]
        for name, (_, argc, arg_usage) in COMMANDS.items():
            suffix = f" {arg_usage}" if arg_usage else ""
            lines.append(f"  - {name}{suffix}")
        return "\n".join(lines)

    if len(sys.argv) < 2:
        raise SystemExit(usage())

    cmd = sys.argv[1]

    if cmd not in COMMANDS:
        raise SystemExit(
            f"Unknown command '{cmd}'.\n\n{usage()}"
        )

    func, argc, arg_usage = COMMANDS[cmd]

    if len(sys.argv) - 2 < argc:
        suffix = f" {arg_usage}" if arg_usage else ""
        raise SystemExit(f"Usage: workflow.py {cmd}{suffix}")

    args = sys.argv[2:]

    result = func(*args) if args else func()

    # ONLY real outputs go to stdout
    if result is not None:
        sys.stdout.write(str(result))
        sys.stdout.flush()

if __name__ == "__main__":
    main()
