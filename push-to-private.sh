#!/usr/bin/env bash
# Push all SideStore branches to your private repo (https://github.com/OofMini/Minis-Store)
#
# SETUP (one-time):
#   1. Create a GitHub Personal Access Token at https://github.com/settings/tokens
#      - Classic token: check "repo" scope
#      - Fine-grained token: grant read+write access to OofMini/Minis-Store
#   2. Add it as a repository secret named MINIS_STORE_TOKEN:
#        https://github.com/OofMini/SideStore/settings/secrets/actions
#      The workflow will then run automatically on every push.
#
# MANUAL RUN:
#   export MINIS_STORE_TOKEN=ghp_yourTokenHere
#   bash push-to-private.sh

set -euo pipefail

PRIVATE_REMOTE_NAME="minis-store"
PRIVATE_REPO_OWNER="OofMini"
PRIVATE_REPO_NAME="Minis-Store"

TOKEN="${MINIS_STORE_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "Error: MINIS_STORE_TOKEN is not set."
  echo "Export it first:  export MINIS_STORE_TOKEN=ghp_yourTokenHere"
  exit 1
fi

REMOTE_URL="https://x-access-token:${TOKEN}@github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}.git"

# Add or update the private remote
if git remote get-url "$PRIVATE_REMOTE_NAME" &>/dev/null; then
  git remote set-url "$PRIVATE_REMOTE_NAME" "$REMOTE_URL"
else
  git remote add "$PRIVATE_REMOTE_NAME" "$REMOTE_URL"
fi

# Verify the remote is reachable before pushing
echo "Checking access to https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME} ..."
if ! git ls-remote "$PRIVATE_REMOTE_NAME" HEAD 2>&1; then
  echo ""
  echo "Error: Cannot reach https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}"
  echo "  - 'Repository not found': repo doesn't exist yet or token lacks access"
  echo "  - 'bad credentials': token is wrong or expired"
  echo "  Create the private repo first at https://github.com/new"
  exit 1
fi
echo "Remote accessible."

# Fetch latest so all remote-tracking refs are up to date
echo "Fetching from origin..."
git fetch --all --prune

# Mirror every origin/* branch to the private remote
echo "Pushing all branches to ${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME} ..."
git push "$PRIVATE_REMOTE_NAME" 'refs/remotes/origin/*:refs/heads/*' --force

echo ""
echo "Done! All branches synced to https://github.com/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}"
