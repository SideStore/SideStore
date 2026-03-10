#!/usr/bin/env bash
# Push all SideStore branches to your private repo (https://github.com/OofMini/Minis-Store)
#
# SETUP (one-time):
#   1. Create a GitHub Personal Access Token at https://github.com/settings/tokens
#      - Classic token: check "repo" scope
#      - Fine-grained token: grant read+write access to OofMini/Minis-Store
#   2. Export your token before running:
#        export MINIS_STORE_TOKEN=ghp_yourTokenHere
#   3. Run this script:
#        bash push-to-private.sh

set -euo pipefail

PRIVATE_REMOTE_NAME="minis-store"
PRIVATE_REPO_OWNER="OofMini"
PRIVATE_REPO_NAME="Minis-Store"

# Resolve token (use MINIS_STORE_TOKEN; GITHUB_TOKEN is reserved by GitHub Actions)
TOKEN="${MINIS_STORE_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "Error: MINIS_STORE_TOKEN is not set."
  echo "Export it first:  export MINIS_STORE_TOKEN=ghp_yourTokenHere"
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

# Verify the remote is reachable before pushing
echo "Checking access to https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME} ..."
if ! git ls-remote "$PRIVATE_REMOTE_NAME" HEAD &>/dev/null; then
  echo ""
  echo "Error: Cannot reach https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}"
  echo "Check that:"
  echo "  1. The repo exists at https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}"
  echo "  2. Your PAT has 'repo' scope (classic) or write access to that repo (fine-grained)"
  exit 1
fi
echo "Remote accessible."

# Fetch latest from origin so all remote-tracking refs are up to date
echo "Fetching latest from origin..."
git fetch --all --prune

# Push every branch from origin/* to the private remote
echo ""
echo "Pushing all branches to $PRIVATE_REPO_OWNER/$PRIVATE_REPO_NAME ..."
git push "$PRIVATE_REMOTE_NAME" 'refs/remotes/origin/*:refs/heads/*' --force

echo ""
echo "Done! All branches are now in your private repo."
echo "Clone URL: https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}"
