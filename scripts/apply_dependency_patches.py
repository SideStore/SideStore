#!/usr/bin/env python3
# Applies patches/<Dependency>/*.patch on top of the checked-out submodules.
# Temporary fixes that can't wait for upstream; delete the patch once upstream has it.
# Safe to run more than once: an already-applied patch is skipped.
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def git_apply(dep_dir, patch, *args):
    return subprocess.run(
        ["git", "-C", str(dep_dir), "apply", *args, str(patch)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )


def main():
    for patch in sorted(ROOT.glob("patches/*/*.patch")):
        dep = patch.parent.name
        dep_dir = ROOT / "Dependencies" / dep
        name = f"{dep}/{patch.name}"

        if git_apply(dep_dir, patch, "--reverse", "--check").returncode == 0:
            print(f"[patches] {name} already applied")
            continue

        check = git_apply(dep_dir, patch, "--check")
        if check.returncode != 0:
            sys.stderr.write(check.stderr)
            sys.exit(f"[patches] {name} does not apply; upstream probably changed, drop or rebase it")

        result = git_apply(dep_dir, patch)
        if result.returncode != 0:
            sys.stderr.write(result.stderr)
            sys.exit(f"[patches] failed to apply {name}")
        print(f"[patches] applied {name}")


if __name__ == "__main__":
    main()
