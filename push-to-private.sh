#!/usr/bin/env bash
# Push SideStore repo to your private repo (https://github.com/OofMini/Minis-Store)
#
# SETUP (one-time):
#   1. Create a GitHub Personal Access Token at https://github.com/settings/tokens
#      - Classic token: check "repo" scope
#      - Fine-grained token: grant read+write access to OofMini/Minis-Store
#   2. Export your token before running:
#        export GITHUB_TOKEN=ghp_yourTokenHere
#   3. Run this script:
#        bash push-to-private.sh
#
# The script pushes the current branch + the 'develop' and 'master' branches.
# Adjust BRANCHES below if you want to push more/fewer branches.

set -euo pipefail

PRIVATE_REMOTE_NAME="minis-store"
PRIVATE_REPO_OWNER="OofMini"
PRIVATE_REPO_NAME="Minis-Store"
BRANCHES=("master" "develop" "claude/fix-pr-issue-KJXhX")

# Resolve token
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set."
  echo "Export it first:  export GITHUB_TOKEN=ghp_yourTokenHere"
  exit 1
fi

REMOTE_URL="https://${TOKEN}@github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}.git"

# Add or update the private remote
if git remote get-url "$PRIVATE_REMOTE_NAME" &>/dev/null; then
  echo "Updating remote '$PRIVATE_REMOTE_NAME'..."
  git remote set-url "$PRIVATE_REMOTE_NAME" "$REMOTE_URL"
else
  echo "Adding remote '$PRIVATE_REMOTE_NAME'..."
  git remote add "$PRIVATE_REMOTE_NAME" "$REMOTE_URL"
fi

# Push each branch
for BRANCH in "${BRANCHES[@]}"; do
  if git show-ref --verify --quiet "refs/heads/$BRANCH" || \
     git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    echo ""
    echo "Pushing '$BRANCH' -> $PRIVATE_REPO_OWNER/$PRIVATE_REPO_NAME ..."
    git push "$PRIVATE_REMOTE_NAME" "refs/remotes/origin/${BRANCH}:refs/heads/${BRANCH}" 2>/dev/null || \
    git push "$PRIVATE_REMOTE_NAME" "${BRANCH}:refs/heads/${BRANCH}"
  else
    echo "Branch '$BRANCH' not found locally or in origin — skipping."
  fi
done

echo ""
echo "Done! Your private repo is up to date."
echo "Clone URL: https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}"
