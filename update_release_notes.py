#!/usr/bin/env python3
import subprocess
import sys
import os
import re

IGNORED_AUTHORS = [

]

TAG_MARKER = "###"
HEADER_MARKER = "####"

def run_command(cmd):
    """Run a shell command and return its trimmed output."""
    return subprocess.check_output(cmd, shell=True, text=True).strip()

def get_head_commit():
    """Return the HEAD commit SHA."""
    return run_command("git rev-parse HEAD")

def get_commit_messages(last_successful, current="HEAD"):
    """Return a list of commit messages between last_successful and current."""
    cmd = f"git log {last_successful}..{current} --pretty=format:%s"
    output = run_command(cmd)
    if not output:
        return []
    return output.splitlines()

def get_authors_in_range(commit_range, fmt="%an"):
    """Return a set of commit authors in the given commit range using the given format."""
    cmd = f"git log {commit_range} --pretty=format:{fmt}"
    output = run_command(cmd)
    if not output:
        return set()
    authors = set(line.strip() for line in output.splitlines() if line.strip())
    authors = set(authors) - set(IGNORED_AUTHORS)
    return authors

def get_first_commit_of_repo():
    """Return the first commit in the repository (root commit)."""
    cmd = "git rev-list --max-parents=0 HEAD"
    output = run_command(cmd)
    return output.splitlines()[0]

def get_branch():
    """
    Attempt to determine the branch base (the commit where the current branch diverged
    from the default remote branch). Falls back to the repo's first commit.
    """
    try:
        default_ref = run_command("git rev-parse --abbrev-ref origin/HEAD")
        default_branch = default_ref.split('/')[-1]
        base_commit = run_command(f"git merge-base HEAD origin/{default_branch}")
        return base_commit
    except Exception:
        return get_first_commit_of_repo()

def get_repo_url():
    """Extract and clean the repository URL from the remote 'origin'."""
    url = run_command("git config --get remote.origin.url")
    if url.startswith("git@"):
        url = url.replace("git@", "https://").replace(":", "/")
    if url.endswith(".git"):
        url = url[:-4]
    return url

def format_contributor(author):
    """
    Convert an author name to a GitHub username or first name.
    If the author already starts with '@', return it;
    otherwise, take the first token and prepend '@'.
    """
    if author.startswith('@'):
        return author
    return f"@{author.split()[0]}"

def format_commit_message(msg):
    """Format a commit message as a bullet point for the release notes."""
    msg_clean = msg.lstrip()  # remove leading spaces
    if msg_clean.startswith("-"):
        msg_clean = msg_clean[1:].strip()  # remove leading '-' and spaces
    return f"- {msg_clean}"

# def generate_release_notes(last_successful, tag, branch):
    """Generate release notes for the given tag."""
    current_commit = get_head_commit()
    messages = get_commit_messages(last_successful, current_commit)
    
    # Start with the tag header
    new_section = f"{TAG_MARKER} {tag}\n"

    # What's Changed section (always present)
    new_section += f"{HEADER_MARKER} What's Changed\n"
    
    if not messages or last_successful == current_commit:
        new_section += "- Nothing...\n"
    else:
        for msg in messages:
            new_section += f"{format_commit_message(msg)}\n"
    
    # New Contributors section (only if there are new contributors)
    all_previous_authors = get_authors_in_range(f"{branch}")
    recent_authors = get_authors_in_range(f"{last_successful}..{current_commit}")
    new_contributors = recent_authors - all_previous_authors
    
    if new_contributors:
        new_section += f"\n{HEADER_MARKER} New Contributors\n"
        for author in sorted(new_contributors):
            new_section += f"- {format_contributor(author)} made their first contribution\n"
    
    # Full Changelog section (only if there are changes)
    if messages and last_successful != current_commit:
        repo_url = get_repo_url()
        changelog_link = f"{repo_url}/compare/{last_successful}...{current_commit}"
        new_section += f"\n{HEADER_MARKER} Full Changelog: [{last_successful[:8]}...{current_commit[:8]}]({changelog_link})\n"
    
    return new_section

def generate_release_notes(last_successful, tag, branch):
    """Generate release notes for the given tag."""
    current_commit = get_head_commit()
    try:
        # Try to get commit messages using the provided last_successful commit
        messages = get_commit_messages(last_successful, current_commit)
    except subprocess.CalledProcessError:
        # If the range is invalid (e.g. force push made last_successful obsolete),
        # fall back to using the last 10 commits in the current branch.
        print("\nInvalid revision range error, using last 10 commits as fallback.\n")
        fallback_commit = run_command("git rev-parse HEAD~5")
        messages = get_commit_messages(fallback_commit, current_commit)
        last_successful = fallback_commit

    # Start with the tag header
    new_section = f"{TAG_MARKER} {tag}\n"

    # What's Changed section (always present)
    new_section += f"{HEADER_MARKER} What's Changed\n"
    
    if not messages or last_successful == current_commit:
        new_section += "- Nothing...\n"
    else:
        for msg in messages:
            new_section += f"{format_commit_message(msg)}\n"
    
    # New Contributors section (only if there are new contributors)
    all_previous_authors = get_authors_in_range(f"{branch}")
    recent_authors = get_authors_in_range(f"{last_successful}..{current_commit}")
    new_contributors = recent_authors - all_previous_authors
    
    if new_contributors:
        new_section += f"\n{HEADER_MARKER} New Contributors\n"
        for author in sorted(new_contributors):
            new_section += f"- {format_contributor(author)} made their first contribution\n"
    
    # Full Changelog section (only if there are changes)
    if messages and last_successful != current_commit:
        repo_url = get_repo_url()
        changelog_link = f"{repo_url}/compare/{last_successful}...{current_commit}"
        new_section += f"\n{HEADER_MARKER} Full Changelog: [{last_successful[:8]}...{current_commit[:8]}]({changelog_link})\n"
    
    return new_section

def update_release_md(existing_content, new_section, tag):
    """
    Update input based on rules:
    1. If tag exists, update it
    2. Special tags (alpha, beta, nightly) stay at the top in that order
    3. Numbered tags follow special tags
    4. Remove duplicate tags
    5. Insert new numbered tags at the top of the numbered section
    """
    tag_lower = tag.lower()
    is_special_tag = tag_lower in ["alpha", "beta", "nightly"]
    
    # Parse the existing content into sections
    if not existing_content:
        return new_section
    
    # Split the content into sections by headers
    pattern = fr'(^{TAG_MARKER} .*$)'
    sections = re.split(pattern, existing_content, flags=re.MULTILINE)
    
    # Create a list to store the processed content
    processed_sections = []
    
    # Track special tag positions and whether tag was found
    special_tags_map = {"alpha": False, "beta": False, "nightly": False}
    last_special_index = -1
    tag_found = False
    numbered_tag_index = -1
    
    i = 0
    while i < len(sections):
        # Check if this is a header
        if i % 2 == 1:  # Headers are at odd indices
            header = sections[i]
            content = sections[i+1] if i+1 < len(sections) else ""
            current_tag = header[3:].strip().lower()
            
            # Check for special tags to track their positions
            if current_tag in special_tags_map:
                special_tags_map[current_tag] = True
                last_special_index = len(processed_sections)
            
            # Check if this is the first numbered tag
            elif re.match(r'^[0-9]+\.[0-9]+(\.[0-9]+)?$', current_tag) and numbered_tag_index == -1:
                numbered_tag_index = len(processed_sections)
            
            # If this is the tag we're updating, mark it but don't add yet
            if current_tag == tag_lower:
                if not tag_found:  # Replace the first occurrence
                    tag_found = True
                    i += 2  # Skip the content
                    continue
                else:  # Skip duplicate occurrences
                    i += 2
                    continue
        
        # Add the current section
        processed_sections.append(sections[i])
        i += 1
    
    # Determine where to insert the new section
    if tag_found:
        # We need to determine the insertion point
        if is_special_tag:
            # For special tags, insert after last special tag or at beginning
            desired_index = -1
            for pos, t in enumerate(["alpha", "beta", "nightly"]):
                if t == tag_lower:
                    desired_index = pos
            
            # Find position to insert
            insert_pos = 0
            for pos, t in enumerate(["alpha", "beta", "nightly"]):
                if t == tag_lower:
                    break
                if special_tags_map[t]:
                    insert_pos = processed_sections.index(f"{TAG_MARKER} {t}")
                    insert_pos += 2  # Move past the header and content
            
            # Insert at the determined position
            processed_sections.insert(insert_pos, new_section)
            if insert_pos > 0 and not processed_sections[insert_pos-1].endswith('\n\n'):
                processed_sections.insert(insert_pos, '\n\n')
        else:
            # For numbered tags, insert after special tags but before other numbered tags
            insert_pos = 0
            
            if last_special_index >= 0:
                # Insert after the last special tag
                insert_pos = last_special_index + 2  # +2 to skip header and content
            
            processed_sections.insert(insert_pos, new_section)
            if insert_pos > 0 and not processed_sections[insert_pos-1].endswith('\n\n'):
                processed_sections.insert(insert_pos, '\n\n')
    else:
        # Tag doesn't exist yet, determine insertion point
        if is_special_tag:
            # For special tags, maintain alpha, beta, nightly order
            special_tags = ["alpha", "beta", "nightly"]
            insert_pos = 0
            
            for i, t in enumerate(special_tags):
                if t == tag_lower:
                    # Check if preceding special tags exist
                    for prev_tag in special_tags[:i]:
                        if special_tags_map[prev_tag]:
                            # Find the position after this tag
                            prev_index = processed_sections.index(f"{TAG_MARKER} {prev_tag}")
                            insert_pos = prev_index + 2  # Skip header and content
            
            processed_sections.insert(insert_pos, new_section)
            if insert_pos > 0 and not processed_sections[insert_pos-1].endswith('\n\n'):
                processed_sections.insert(insert_pos, '\n\n')
        else:
            # For numbered tags, insert after special tags but before other numbered tags
            insert_pos = 0
            
            if last_special_index >= 0:
                # Insert after the last special tag
                insert_pos = last_special_index + 2  # +2 to skip header and content
            
            processed_sections.insert(insert_pos, new_section)
            if insert_pos > 0 and not processed_sections[insert_pos-1].endswith('\n\n'):
                processed_sections.insert(insert_pos, '\n\n')
    
    # Combine sections ensuring proper spacing
    result = ""
    for i, section in enumerate(processed_sections):
        if i > 0 and section.startswith(f"{TAG_MARKER} "):
            # Ensure single blank line before headers
            if not result.endswith("\n\n"):
                result = result.rstrip("\n") + "\n\n"
        result += section
    
    return result.rstrip() + "\n"


def retrieve_tag_content(tag, file_path):
    if not os.path.exists(file_path):
        return ""
    
    with open(file_path, "r") as f:
        content = f.read()
    
    # Create a pattern for the tag header (case-insensitive)
    pattern = re.compile(fr'^{TAG_MARKER} ' + re.escape(tag) + r'$', re.MULTILINE | re.IGNORECASE)
    
    # Find the tag header
    match = pattern.search(content)
    if not match:
        return ""
    
    # Start after the tag line
    start_pos = match.end()
    
    # Skip a newline if present
    if start_pos < len(content) and content[start_pos] == "\n":
        start_pos += 1
    
    # Find the next tag header after the current tag's content
    next_tag_match = re.search(fr'^{TAG_MARKER} ', content[start_pos:], re.MULTILINE)
    
    if next_tag_match:
        end_pos = start_pos + next_tag_match.start()
        return content[start_pos:end_pos].strip()
    else:
        # Return until the end of the file if this is the last tag
        return content[start_pos:].strip()

def main():
    # Update input file
    release_file = "release-notes.md"

    # Usage: python release.py <last_successful_commit> [tag] [branch]
    # Or: python release.py --retrieve <tagname>
    args = sys.argv[1:]
    
    if len(args) < 1:
        print("Usage: python release.py <last_successful_commit> [tag] [branch]")
        print("   or: python release.py --retrieve <tagname>")
        sys.exit(1)
    
    # Check if we're retrieving a tag
    if args[0] == "--retrieve":
        if len(args) < 2:
            print("Error: Missing tag name after --retrieve")
            sys.exit(1)
        
        tag_content = retrieve_tag_content(args[1], file_path=release_file)
        if tag_content:
            print(tag_content)
        else:
            print(f"Tag '{args[1]}' not found in '{release_file}'")
        return
    
    # Original functionality for generating release notes
    last_successful = args[0]
    tag = args[1] if len(args) > 1 else get_head_commit()
    branch = args[2] if len(args) > 2 else (os.environ.get("GITHUB_REF") or get_branch())
    
    # Generate release notes
    new_section = generate_release_notes(last_successful, tag, branch)
    
    existing_content = ""
    if os.path.exists(release_file):
        with open(release_file, "r") as f:
            existing_content = f.read()
    
    updated_content = update_release_md(existing_content, new_section, tag)
    
    with open(release_file, "w") as f:
        f.write(updated_content)
    
    # Output the new section for display
    print(new_section)

if __name__ == "__main__":
    main()
