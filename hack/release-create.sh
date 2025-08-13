#!/usr/bin/env bash

#
# Create a new Cloudy Pad release with Git tag and container images
#

# If dry run enabled
# - Docker images are built but not pushed
# - Git branch created but not pushed
# - Version changes are committed but not pushed
# - Git tag not created
# - GitHub PRs not created
# - GitHub release not created
CLOUDYPAD_RELEASE_DRY_RUN=${CLOUDYPAD_RELEASE_DRY_RUN:-false}

# Update versions in package files and scripts
# install.sh, cloudypad.sh, package.json, flake.nix
update_versions_in_package_files() {
  release_version=$1

  echo "Updating Cloudy Pad version in package files and scripts..."

  VERSION_REGEX="[0-9]\+\.[0-9]\+\.[0-9]\+\([-a-zA-Z0-9]*\)\?"

  echo "Updating CLOUDYPAD_VERSION in cloudypad.sh and install.sh..."

  # Replace CLOUDYPAD_VERSION in cloudypad.sh with any semantic version including those with additional characters
  sed -i "s/CLOUDYPAD_VERSION=$VERSION_REGEX/CLOUDYPAD_VERSION=$release_version/" cloudypad.sh
  sed -i "s/DEFAULT_CLOUDYPAD_SCRIPT_REF=v$VERSION_REGEX/DEFAULT_CLOUDYPAD_SCRIPT_REF=v$release_version/" install.sh

  echo "Updating version in package.json..."
  sed -i "s/\"version\": \"$VERSION_REGEX\"/\"version\": \"$release_version\"/" package.json

  echo "Updating version and hash in flake.nix..."
  sed -i "s/cloudypadVersion = \"$VERSION_REGEX\";/cloudypadVersion = \"$release_version\";/" flake.nix

  # Make sure the hash of cloudypad.sh matches the one in pkgs.fetchurl cloudypad.sh from flake.nix
  # Compute SRI sha256 using OpenSSL (avoids nix-prefetch-url dependency)
  if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl is required to compute SRI hash." >&2
    exit 1
  fi

  CLOUDYPAD_SRI=$(openssl dgst -sha256 -binary "$PWD/cloudypad.sh" | openssl base64 -A)
  # Update either old style (sha256:...) or SRI (sha256-...) in flake.nix
  sed -i "s|hash = \"sha256[^\"]*\";|hash = \"sha256-${CLOUDYPAD_SRI}\";|" flake.nix
}

create_push_release_branch() {
  release_version=$1
  release_branch="release-$release_version"

  read -p "New version: $release_version with release branch '$release_branch'. Continue? (If something goes wrong, delete branch and try again)"

  echo "Checking out branch '$release_branch'..."

  # If there are local changes, stash them so checkout can't fail
  STASHED=false
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Worktree is dirty. Stashing changes temporarily..."
    git stash push -u -m "release-create temp $(date -Iseconds)"
    STASHED=true
  fi

  # Reuse existing branch (local or remote) or create it
  if git show-ref --verify --quiet "refs/heads/$release_branch"; then
    echo "Branch '$release_branch' exists locally. Reusing it."
    git checkout "$release_branch"
  elif git ls-remote --exit-code --heads origin "$release_branch" >/dev/null 2>&1; then
    echo "Branch '$release_branch' exists on origin. Creating local tracking branch."
    git fetch origin "$release_branch:$release_branch"
    git checkout "$release_branch"
  else
    echo "Creating new branch '$release_branch'..."
    git checkout -b "$release_branch"
  fi

  # Restore stashed changes onto the release branch
  if [ "$STASHED" = true ]; then
    echo "Restoring stashed changes onto '$release_branch'..."
    if ! git stash pop; then
      echo "Automatic stash pop resulted in conflicts. Resolve them, then run:"
      echo "  git add -A && git commit -m \"chore: prepare release $release_version - update version in package files and scripts\""
      exit 1
    fi
  fi

  echo "Committing and pushing version changes to $release_branch..."
  git add package.json cloudypad.sh install.sh flake.nix
  if git diff --cached --quiet; then
    echo "No changes to commit."
  else
    git commit -m "chore: prepare release $release_version - update version in package files and scripts"
  fi

  if [ "$CLOUDYPAD_RELEASE_DRY_RUN" = true ]; then
    echo "Dry run enabled: Skipping git push."
  else
    # Ensure upstream is set the first time
    if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      git push
    else
      git push -u origin "$release_branch"
    fi
  fi
}
run_release_please() {
  if command -v npx >/dev/null 2>&1; then
    npx --yes release-please "$@"
  elif command -v npm >/dev/null 2>&1; then
    npm exec --yes -- release-please "$@"
  elif command -v release-please >/dev/null 2>&1; then
    release-please "$@"
  else
    echo "Error: neither npx, npm, nor release-please found. Install Node.js or 'npm i -g release-please'." >&2
    exit 1
  fi
}
create_release_pr_and_merge_in_release_branch() {
  release_version=$1
  release_branch="release-$release_version"

  if [ "$CLOUDYPAD_RELEASE_DRY_RUN" = true ]; then
    echo "Dry run enabled: Skipping release PR creation and merge."
    return
  fi

  echo "Creating release PR..."
  run_release_please release-pr \
    --repo-url https://github.com/ap0ught/cloudypad \
    --token "$GITHUB_TOKEN" \
    --target-branch "$release_branch"

  echo "Release is ready to be merged in release branch."
  gh pr merge "release-please--branches--$release_branch--components--cloudypad" --merge || true

  echo "Pulling Release Please changes in $release_branch..."
  git pull

  echo "Creating GitHub release for v$release_version (as prerelease)..."
  run_release_please github-release \
    --repo-url https://github.com/ap0ught/cloudypad \
    --token="$GITHUB_TOKEN" \
    --target-branch "$release_branch" \
    --prerelease

  # Explicitly mark the intended tag as prerelease (do NOT rely on 'latest')
  echo "Marking v$release_version as prerelease"
  gh release edit "v$release_version" --prerelease || true
}
merge_release_branch_in_master() {
  release_version=$1
  release_branch="release-$release_version"
  release_tag="v$release_version"

  if [ "$CLOUDYPAD_RELEASE_DRY_RUN" = true ]; then
    echo "Dry run enabled: Skipping release branch merge in master."
    return
  fi

  echo "Waiting for CI jobs on tag $release_tag..."
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "ap0ught/cloudypad")"
  tag_sha="$(git rev-list -n 1 "$release_tag")"

  timeout=3600
  start_time=$(date +%s)
  release_jobs_success=false

  # Find a workflow run that matches the tag's commit SHA
  find_run_id() {
    gh api "repos/$repo/actions/runs?per_page=100" \
      | jq -r --arg sha "$tag_sha" '.workflow_runs[] | select(.head_sha==$sha) | .id' \
      | head -n1
  }

  run_id="$(find_run_id)"
  if [ -z "$run_id" ]; then
    echo "No workflow run found yet for $release_tag (sha $tag_sha). Waiting for it to appear..."
  fi

  while true; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ $elapsed_time -ge $timeout ]; then
      echo "Timeout reached: CI jobs did not complete within $timeout seconds."
      exit 1
    fi

    if [ -z "$run_id" ]; then
      run_id="$(find_run_id)"
      sleep 10
      continue
    fi

    run_json="$(gh api "repos/$repo/actions/runs/$run_id")"
    status="$(echo "$run_json" | jq -r '.status')"
    conclusion="$(echo "$run_json" | jq -r '.conclusion')"
    name="$(echo "$run_json" | jq -r '.name')"
    echo "[$(date +%Y-%m-%d-%H:%M:%S)] Run $run_id '$name' status: $status, conclusion: $conclusion"

    if [ "$status" = "completed" ]; then
      if [ "$conclusion" = "success" ]; then
        release_jobs_success=true
        echo "CI completed successfully for $release_tag."
      else
        echo "CI completed but not successful for $release_tag (conclusion: $conclusion)."
      fi
      break
    fi
    sleep 20
  done

  read -p "Merge release branch $release_branch into master? (y/N): " confirm_merge
  if [[ "$confirm_merge" != "y" ]]; then
    echo "Merge aborted."
    exit 1
  fi

  if [ "$release_jobs_success" = true ]; then
    echo "Merging release branch $release_branch into master..."
    gh pr create --title "Finalize release $release_version" --body "" --base master --head "$release_branch" || true
    gh pr merge "$release_branch" --merge

    echo "Marking v$release_version as latest (not prerelease)"
    gh release edit "v$release_version" --latest --prerelease=false

    echo "Checking out and pulling master after release..."
    git checkout master && git pull
  else
    echo "CI did not succeed for $release_tag."
    exit 1
  fi
}
set -e

if [ -z ${GITHUB_TOKEN+x} ]; then 
    echo "GITHUB_TOKEN variable must be set (with read/write permissions on content and pull requests)"
    exit 1
fi

if [ -z "$1" ]; then
  read -p "Release version? " release_version
else 
    release_version=$1
fi

update_versions_in_package_files $release_version
create_push_release_branch $release_version

create_release_pr_and_merge_in_release_branch $release_version
merge_release_branch_in_master $release_version

echo "Release done ! ✨"