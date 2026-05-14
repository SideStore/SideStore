#!/usr/bin/env python3
import subprocess
import sys
import os
import re
from pathlib import Path

IGNORED_AUTHORS = []

TAG_MARKER = "###"
HEADER_MARKER = "####"


# ----------------------------------------------------------
# helpers
# ----------------------------------------------------------

def run(cmd: str) -> str:
    return subprocess.check_output(cmd, shell=True, text=True).strip()


def commit_exists(rev: str) -> bool:
    if not rev:
        return False
    try:
        subprocess.check_output(
            f"git rev-parse --verify {rev}^{{commit}}",
            shell=True,
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def head_commit():
    return run("git rev-parse HEAD")


def first_commit():
    return run("git rev-list --max-parents=0 HEAD").splitlines()[0]


def repo_url():
    url = run("git config --get remote.origin.url")
    if url.startswith("git@"):
        url = url.replace("git@", "https://").replace(":", "/")
    return url.removesuffix(".git")


def commit_messages(start, end="HEAD"):
    out = run(f"git log {start}..{end} --pretty=format:%s")
    return out.splitlines() if out else []


def authors(range_expr, fmt="%an"):
    try:
        out = run(f"git log {range_expr} --pretty=format:{fmt}")
        result = {a.strip() for a in out.splitlines() if a.strip()}
        return result - set(IGNORED_AUTHORS)
    except subprocess.CalledProcessError:
        return set()


def branch_base():
    try:
        default_ref = run("git rev-parse --abbrev-ref origin/HEAD")
        default_branch = default_ref.split("/")[-1]
        return run(f"git merge-base HEAD origin/{default_branch}")
    except Exception:
        return first_commit()


def fmt_msg(msg):
    msg = msg.lstrip()
    if msg.startswith("-"):
        msg = msg[1:].strip()
    return f"- {msg}"


def fmt_author(author):
    return author if author.startswith("@") else f"@{author.split()[0]}"


# ----------------------------------------------------------
# release note generation
# ----------------------------------------------------------

def resolve_start_commit(last_successful: str):
    if commit_exists(last_successful):
        return last_successful

    try:
        return run("git rev-parse HEAD~10")
    except Exception:
        return first_commit()


def generate_release_notes(last_successful, tag, branch):
    current = head_commit()

    # fallback if missing/invalid
    if not last_successful or not commit_exists(last_successful):
        try:
            last_successful = run("git rev-parse HEAD~10")
        except Exception:
            last_successful = first_commit()

    messages = commit_messages(last_successful, current)

    # fallback if empty range
    if not messages:
        try:
            last_successful = run("git rev-parse HEAD~10")
        except Exception:
            last_successful = first_commit()
        messages = commit_messages(last_successful, current)

    section = f"{TAG_MARKER} {tag}\n"
    section += f"{HEADER_MARKER} What's Changed\n"

    if not messages or last_successful == current:
        section += "- Nothing...\n"
    else:
        for m in messages:
            section += f"{fmt_msg(m)}\n"

    if commit_exists(branch):
        previous_range = branch
    else:
        previous_range = last_successful

    prev_authors = authors(previous_range)
    recent_authors = authors(f"{last_successful}..{current}")
    new_authors = recent_authors - prev_authors

    if new_authors:
        section += f"\n{HEADER_MARKER} New Contributors\n"
        for a in sorted(new_authors):
            section += f"- {fmt_author(a)} made their first contribution\n"

    if messages and last_successful != current:
        url = repo_url()
        section += (
            f"\n{HEADER_MARKER} Full Changelog: "
            f"[{ref_display(last_successful)}...{ref_display(current)}]"
            f"({url}/compare/{last_successful}...{current})\n"
        )

    return section


def ref_display(ref):
    try:
        tag = run(f'git describe --tags --exact-match "{ref}" 2>/dev/null || true').strip()

        # allow only semantic version tags: X.Y.Z
        if re.fullmatch(r'\d+\.\d+\.\d+', tag):
            return tag
    except Exception:
        pass

    return ref[:8]


# ----------------------------------------------------------
# markdown update
# ----------------------------------------------------------

def update_release_md(existing, new_section, tag):
    if not existing:
        return new_section

    tag_lower = tag.lower()
    is_special = tag_lower in {"alpha", "beta", "nightly"}

    pattern = fr"(^{TAG_MARKER} .*$)"
    parts = re.split(pattern, existing, flags=re.MULTILINE)

    processed = []
    special_seen = {"alpha": False, "beta": False, "nightly": False}
    last_special_idx = -1

    i = 0
    while i < len(parts):
        if i % 2 == 1:
            header = parts[i]
            name = header[3:].strip().lower()

            if name in special_seen:
                special_seen[name] = True
                last_special_idx = len(processed)

            if name == tag_lower:
                i += 2
                continue

        processed.append(parts[i])
        i += 1

    insert_pos = 0
    if is_special:
        order = ["alpha", "beta", "nightly"]
        for t in order:
            if t == tag_lower:
                break
            if special_seen[t]:
                idx = processed.index(f"{TAG_MARKER} {t}")
                insert_pos = idx + 2
    elif last_special_idx >= 0:
        insert_pos = last_special_idx + 2

    processed.insert(insert_pos, new_section)

    result = ""
    for part in processed:
        if part.startswith(f"{TAG_MARKER} ") and not result.endswith("\n\n"):
            result = result.rstrip("\n") + "\n\n"
        result += part

    return result.rstrip() + "\n"


# ----------------------------------------------------------
# retrieval
# ----------------------------------------------------------

def retrieve_tag(tag, file_path: Path):
    if not file_path.exists():
        return ""

    content = file_path.read_text()

    match = re.search(
        fr"^{TAG_MARKER} {re.escape(tag)}$",
        content,
        re.MULTILINE | re.IGNORECASE,
        )

    if not match:
        return ""

    start = match.end()
    if start < len(content) and content[start] == "\n":
        start += 1

    next_tag = re.search(fr"^{TAG_MARKER} ", content[start:], re.MULTILINE)
    end = start + next_tag.start() if next_tag else len(content)

    return content[start:end].strip()


# ----------------------------------------------------------
# entrypoint
# ----------------------------------------------------------

def main():
    args = sys.argv[1:]

    if not args:
        sys.exit(
            "Usage:\n"
            "  generate_release_notes.py <last_successful> [tag] [branch] [--output-dir DIR]\n"
            "  generate_release_notes.py --retrieve <tag> [--output-dir DIR]"
        )

    output_dir = Path.cwd()

    if "--output-dir" in args:
        idx = args.index("--output-dir")
        output_dir = Path(args[idx + 1]).resolve()
        del args[idx:idx + 2]

    output_dir.mkdir(parents=True, exist_ok=True)
    release_file = output_dir / "release-notes.md"

    if args[0] == "--retrieve":
        print(retrieve_tag(args[1], release_file))
        return

    last_successful = args[0]
    tag = args[1] if len(args) > 1 else head_commit()
    branch = args[2] if len(args) > 2 else (
        os.environ.get("GITHUB_REF") or branch_base()
    )

    new_section = generate_release_notes(last_successful, tag, branch)

    existing = release_file.read_text() if release_file.exists() else ""
    updated = update_release_md(existing, new_section, tag)

    release_file.write_text(updated)

    print(new_section)


if __name__ == "__main__":
    main()
