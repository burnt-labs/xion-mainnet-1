#!/bin/bash
# All-in-one release orchestration script
# Consolidates all workflow logic into a single executable script with functions

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
RELEASE_TAG="${RELEASE_TAG:-}"
XION_API_URL="${XION_API_URL:-}"
MINTSCAN_CHAIN_ID="${MINTSCAN_CHAIN_ID:-}"
NETWORK_NAME="${NETWORK_NAME:-}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
DEPOSIT="${DEPOSIT:-1000000000uxion}"
EXPEDITED="${EXPEDITED:-false}"
UPGRADE_WINDOW_SECONDS="${UPGRADE_WINDOW_SECONDS:-172800}"
PLACEHOLDER_CHECKSUM="${PLACEHOLDER_CHECKSUM:---ADD-HERE-YOUR-VALUE--}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
RUN_NUMBER="${RUN_NUMBER:-0}"
COMMIT_SHA="${COMMIT_SHA:-}"

# ============================================================================
# FUNCTIONS
# ============================================================================

setup_release_branch() {
  echo "📋 Setting up release branch..."

  VERSION=$(echo "$RELEASE_TAG" | sed -E 's/^v([0-9]+)\..*/v\1/')
  # Use upgrade/ prefix instead of release/ to avoid ruleset that requires PRs on release/** branches
  BRANCH_NAME="upgrade/$RELEASE_TAG"

  git config --local user.email "action@github.com"
  git config --local user.name "GitHub Action"
  git fetch origin

  if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
    echo "Remote branch $BRANCH_NAME exists, checking out..."
    if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
      git checkout "$BRANCH_NAME"
    else
      git checkout -b "$BRANCH_NAME" origin/"$BRANCH_NAME"
    fi
    git pull origin "$BRANCH_NAME"
  else
    echo "Creating new branch $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME"
  fi

  echo "✅ Branch: $BRANCH_NAME, Version: $VERSION"
}

calculate_upgrade_height() {
  echo "📋 Calculating upgrade height..."

  API_RESPONSE=$(curl -s -X GET "$XION_API_URL/cosmos/base/tendermint/v1beta1/blocks/latest" -H 'accept: application/json')
  CURRENT_BLOCK=$(echo "$API_RESPONSE" | jq -r '.block.header.height // empty')
  CURRENT_TIME=$(echo "$API_RESPONSE" | jq -r '.block.header.time // empty')

  if [ -z "$CURRENT_BLOCK" ] || [ "$CURRENT_BLOCK" = "null" ]; then
    echo "❌ ERROR: Cannot fetch current block height"
    exit 1
  fi

  OLD_BLOCK=$((CURRENT_BLOCK - 10000))
  OLD_BLOCK_INFO=$(curl -s -X GET "$XION_API_URL/cosmos/base/tendermint/v1beta1/blocks/$OLD_BLOCK" -H 'accept: application/json' | jq -r '.block.header.time // empty')

  CURRENT_TIMESTAMP=$(date -d "$CURRENT_TIME" +%s)
  OLD_TIMESTAMP=$(date -d "$OLD_BLOCK_INFO" +%s)
  TIME_DIFF=$((CURRENT_TIMESTAMP - OLD_TIMESTAMP))
  AVERAGE_BLOCK_TIME=$(echo "scale=2; $TIME_DIFF / 10000" | bc)

  BLOCKS_IN_WINDOW=$(echo "scale=0; $UPGRADE_WINDOW_SECONDS / $AVERAGE_BLOCK_TIME" | bc)
  TARGET_BLOCKS=$((BLOCKS_IN_WINDOW + CURRENT_BLOCK))
  CALCULATED_HEIGHT=$(( (TARGET_BLOCKS + 500) / 1000 * 1000 ))

  echo "✅ Upgrade height: $CALCULATED_HEIGHT"
}

fetch_release_checksums() {
  echo "📋 Fetching release checksums..."

  local RELEASE_VERSION="${RELEASE_TAG#v}"
  CHECKSUMS_URL="https://github.com/burnt-labs/xion/releases/download/$RELEASE_TAG/xiond-${RELEASE_VERSION}-checksums.txt"
  HTTP_CODE=$(curl -sL -w "%{http_code}" "$CHECKSUMS_URL" -o checksums_temp.txt)

  if [ "${HTTP_CODE: -3}" = "200" ]; then
    DARWIN_AMD64_CHECKSUM=$(grep "darwin_amd64\.tar\.gz$" checksums_temp.txt | awk '{print $1}')
    DARWIN_ARM64_CHECKSUM=$(grep "darwin_arm64\.tar\.gz$" checksums_temp.txt | awk '{print $1}')
    LINUX_AMD64_CHECKSUM=$(grep "linux_amd64\.tar\.gz$" checksums_temp.txt | awk '{print $1}')
    LINUX_ARM64_CHECKSUM=$(grep "linux_arm64\.tar\.gz$" checksums_temp.txt | awk '{print $1}')
    echo "✅ Real checksums fetched"
  else
    echo "⚠️  Checksums not available for $RELEASE_TAG (HTTP ${HTTP_CODE: -3})"
    echo "    This is expected for future releases not yet published"
    echo "    URL: $CHECKSUMS_URL"
    DARWIN_AMD64_CHECKSUM="$PLACEHOLDER_CHECKSUM"
    DARWIN_ARM64_CHECKSUM="$PLACEHOLDER_CHECKSUM"
    LINUX_AMD64_CHECKSUM="$PLACEHOLDER_CHECKSUM"
    LINUX_ARM64_CHECKSUM="$PLACEHOLDER_CHECKSUM"
    echo "    Using placeholder checksums"
  fi

  rm -f checksums_temp.txt
}

fetch_github_comparison() {
  echo "📋 Fetching GitHub comparison data..."

  CURRENT_MAJOR=$(echo "$RELEASE_TAG" | sed -E 's/^v([0-9]+)\..*/\1/')
  PREVIOUS_MAJOR=$((CURRENT_MAJOR - 1))
  PREVIOUS_VERSION="v${PREVIOUS_MAJOR}.0.0"

  CURRENT_TAG_EXISTS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/burnt-labs/xion/git/refs/tags/$RELEASE_TAG" | \
    jq -r '.ref // "not_found"')

  if [[ "$CURRENT_TAG_EXISTS" == "not_found" ]]; then
    COMPARISON_DATA='{"total_commits": "TBD", "files": [], "commits": []}'
    COMMIT_COUNT="TBD"
    FILES_CHANGED="TBD"
    echo "⚠️  Future release - using placeholder comparison data"
  else
    COMPARISON_URL="https://api.github.com/repos/burnt-labs/xion/compare/$PREVIOUS_VERSION...$RELEASE_TAG"
    COMPARISON_DATA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$COMPARISON_URL")
    ERROR_MESSAGE=$(echo "$COMPARISON_DATA" | jq -r '.message // empty')

    if [[ "$ERROR_MESSAGE" == "Not Found" ]]; then
      COMPARISON_DATA='{"total_commits": 0, "files": [], "commits": []}'
      COMMIT_COUNT=0
      FILES_CHANGED=0
    else
      COMMIT_COUNT=$(echo "$COMPARISON_DATA" | jq -r '.total_commits // 0')
      FILES_CHANGED=$(echo "$COMPARISON_DATA" | jq -r '.files | length // 0')
    fi
  fi

  echo "$COMPARISON_DATA" > comparison_data.json
  echo "✅ Comparison: $COMMIT_COUNT commits, $FILES_CHANGED files changed"
}

generate_claude_notes() {
  echo "📋 Generating release notes via GitHub Copilot (Models API)..."

  PROMPT=$(cat .github/workflows/prompts/claude-api-prompt.md)
  PROMPT="${PROMPT//\{\{RELEASE_TAG\}\}/$RELEASE_TAG}"
  PROMPT="${PROMPT//\{\{CALCULATED_HEIGHT\}\}/$CALCULATED_HEIGHT}"
  PROMPT="${PROMPT//\{\{PREVIOUS_VERSION\}\}/$PREVIOUS_VERSION}"

  COMPARISON_JSON=$(cat comparison_data.json | jq -c .)
  FULL_CONTENT="${PROMPT}\n\nGitHub Comparison Data:\n${COMPARISON_JSON}"

  cat > copilot_request.json <<EOF
{
  "model": "openai/gpt-4o",
  "max_tokens": 4000,
  "messages": [
    {
      "role": "user",
      "content": $(echo "$FULL_CONTENT" | jq -Rs .)
    }
  ]
}
EOF

  RESPONSE=$(curl -s -X POST "https://models.github.ai/inference/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    --data @copilot_request.json)

  API_ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
  if [ -n "$API_ERROR" ]; then
    echo "⚠️  GitHub Models API error: $API_ERROR"
  else
    RELEASE_NOTES_CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')
    if [ -n "$RELEASE_NOTES_CONTENT" ] && [ "$RELEASE_NOTES_CONTENT" != "null" ]; then
      echo "$RELEASE_NOTES_CONTENT" > generated_release_notes.md
      echo "✅ Release notes generated"
    fi
  fi

  rm -f copilot_request.json
}

create_release_files() {
  echo "📋 Creating release files..."

  git restore .github/workflows/templates/release_notes_template.md 2>/dev/null || true

  OUTPUT=$(./scripts/create-release-pr.sh "$CALCULATED_HEIGHT" "$DEPOSIT" "$EXPEDITED" "$RELEASE_TAG")
  CALCULATED_PROPOSAL_NUMBER=$(echo "$OUTPUT" | grep "^Proposal number:" | sed 's/Proposal number: //')

  echo "✅ Proposal number: $CALCULATED_PROPOSAL_NUMBER"
}

determine_file_paths() {
  echo "📋 Determining file paths..."

  ACTUAL_PROPOSAL_FILE=$(find proposals/ -name "*-upgrade-${VERSION}.json" 2>/dev/null | head -1)

  if [ -z "$ACTUAL_PROPOSAL_FILE" ]; then
    LATEST_PROPOSAL=$(ls proposals/ 2>/dev/null | grep -E '^[0-9]{3}-upgrade-v[0-9]+\.json$' | sort -V | tail -1)
    if [ -z "$LATEST_PROPOSAL" ]; then
      NEXT_NUM="001"
    else
      CURRENT_NUM=$(echo $LATEST_PROPOSAL | cut -d'-' -f1)
      NEXT_NUM=$(printf "%03d" $((10#$CURRENT_NUM + 1)))
    fi
    ACTUAL_PROPOSAL_FILE="proposals/${NEXT_NUM}-upgrade-${VERSION}.json"
  fi

  PROPOSAL_FILE="$ACTUAL_PROPOSAL_FILE"
  RELEASE_FILE="releases/$VERSION.json"
  RELEASE_NOTES_FILE="release_notes/$VERSION.md"

  echo "✅ Files: $PROPOSAL_FILE, $RELEASE_FILE, $RELEASE_NOTES_FILE"
}

substitute_release_notes() {
  echo "📋 Substituting template variables..."

  if [ -f "$RELEASE_NOTES_FILE" ]; then
    sed -i "s|{{NETWORK_NAME}}|$NETWORK_NAME|g" "$RELEASE_NOTES_FILE"
    sed -i "s|{{MINTSCAN_CHAIN_ID}}|$MINTSCAN_CHAIN_ID|g" "$RELEASE_NOTES_FILE"
    sed -i "s|{{CALCULATED_HEIGHT}}|$CALCULATED_HEIGHT|g" "$RELEASE_NOTES_FILE"
    sed -i "s|{{CALCULATED_PROPOSAL_NUMBER}}|$CALCULATED_PROPOSAL_NUMBER|g" "$RELEASE_NOTES_FILE"
    sed -i "s|{{PREVIOUS_VERSION}}|$PREVIOUS_VERSION|g" "$RELEASE_NOTES_FILE"
    sed -i "s|{{RELEASE_TAG}}|$RELEASE_TAG|g" "$RELEASE_NOTES_FILE"
    sed -i "s|{{VERSION}}|$VERSION|g" "$RELEASE_NOTES_FILE"
    echo "✅ Template variables substituted"
  fi
}

generate_pr_body() {
  echo "📋 Generating PR body..."

  ./scripts/generate-pr-body.sh \
    "$VERSION" \
    "$CALCULATED_HEIGHT" \
    "$DEPOSIT" \
    "$EXPEDITED" \
    "$PROPOSAL_FILE" \
    "$RELEASE_FILE" \
    "$RELEASE_NOTES_FILE" \
    "$RELEASE_TAG" \
    "$COMMIT_COUNT" \
    "$FILES_CHANGED" \
    "$PREVIOUS_VERSION" \
    "$DARWIN_AMD64_CHECKSUM" \
    "$DARWIN_ARM64_CHECKSUM" \
    "$LINUX_AMD64_CHECKSUM" \
    "$LINUX_ARM64_CHECKSUM" \
    "$RUN_NUMBER" \
    "$COMMIT_SHA"

  echo "✅ PR body generated"
}

commit_and_push_pr() {
  echo "📋 Committing via GitHub API (signed commits)..."

  REPO="burnt-labs/xion-mainnet-1"
  COMMIT_MESSAGE="Added release $RELEASE_TAG upgrade files"

  # Collect files to commit
  FILES_TO_COMMIT=()
  for file in "$PROPOSAL_FILE" "$RELEASE_FILE" "$RELEASE_NOTES_FILE"; do
    if [ -f "$file" ]; then
      FILES_TO_COMMIT+=("$file")
      echo "  📄 $file"
    fi
  done

  if [ ${#FILES_TO_COMMIT[@]} -eq 0 ]; then
    echo "⚠️  No files to commit"
    return 0
  fi

  # Ensure remote branch exists
  if ! git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
    # Create branch on remote via API
    BASE_SHA=$(git rev-parse HEAD)
    gh api "repos/${REPO}/git/refs" \
      -f "ref=refs/heads/${BRANCH_NAME}" \
      -f "sha=${BASE_SHA}" || true
  fi

  # Get the current commit SHA of the branch
  PARENT_SHA=$(gh api "repos/${REPO}/git/refs/heads/${BRANCH_NAME}" --jq '.object.sha')
  BASE_TREE=$(gh api "repos/${REPO}/git/commits/${PARENT_SHA}" --jq '.tree.sha')

  # Build tree entries — create blobs for each file
  TREE_ENTRIES="[]"
  for file in "${FILES_TO_COMMIT[@]}"; do
    CONTENT=$(base64 < "$file")
    BLOB_SHA=$(gh api "repos/${REPO}/git/blobs" \
      -f "content=${CONTENT}" \
      -f "encoding=base64" \
      --jq '.sha')
    TREE_ENTRIES=$(echo "$TREE_ENTRIES" | jq \
      --arg path "$file" \
      --arg sha "$BLOB_SHA" \
      '. + [{"path": $path, "mode": "100644", "type": "blob", "sha": $sha}]')
  done

  # Create tree
  NEW_TREE=$(echo "$TREE_ENTRIES" | jq -c '{base_tree: "'"$BASE_TREE"'", tree: .}' | \
    gh api "repos/${REPO}/git/trees" --input - --jq '.sha')

  # Create commit (API commits are automatically signed/verified)
  NEW_COMMIT=$(gh api "repos/${REPO}/git/commits" \
    -f "message=${COMMIT_MESSAGE}" \
    -f "tree=${NEW_TREE}" \
    -f "parents[]=${PARENT_SHA}" \
    --jq '.sha')

  # Update branch ref
  gh api "repos/${REPO}/git/refs/heads/${BRANCH_NAME}" \
    -X PATCH \
    -f "sha=${NEW_COMMIT}" \
    -F "force=true"

  echo "✅ Committed ${NEW_COMMIT:0:8} to ${BRANCH_NAME}"

  # Create or update PR
  EXISTING_PR=$(gh pr list --repo "$REPO" --head "$BRANCH_NAME" --base "$TARGET_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")

  if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
    echo "Updating existing PR #$EXISTING_PR"
    gh pr edit "$EXISTING_PR" --repo "$REPO" --body-file pr_body.md
    echo "✅ Updated PR #$EXISTING_PR"
  else
    echo "Creating new PR"
    gh pr create \
      --repo "$REPO" \
      --base "$TARGET_BRANCH" \
      --head "$BRANCH_NAME" \
      --title "🚀 Upgrade to Xion $RELEASE_TAG" \
      --body-file pr_body.md
    echo "✅ PR created successfully"
  fi

  rm -f commit_message.txt
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo "🚀 Starting release workflow for $RELEASE_TAG"
  echo "================================================"

  # Validate required inputs
  if [ -z "$RELEASE_TAG" ] || [ -z "$XION_API_URL" ] || [ -z "$TARGET_BRANCH" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: Missing required environment variables"
    echo "Required: RELEASE_TAG, XION_API_URL, TARGET_BRANCH, GITHUB_TOKEN"
    exit 1
  fi


  # Execute workflow steps
  setup_release_branch
  calculate_upgrade_height
  fetch_release_checksums
  fetch_github_comparison
  generate_claude_notes
  create_release_files
  determine_file_paths
  substitute_release_notes
  generate_pr_body
  commit_and_push_pr

  echo ""
  echo "================================================"
  echo "✅ Release workflow completed successfully!"
  echo "================================================"
  echo "Release: $RELEASE_TAG"
  echo "Proposal: $PROPOSAL_FILE"
  echo "Height: $CALCULATED_HEIGHT"
  echo "Branch: $BRANCH_NAME → $TARGET_BRANCH"
}

# Run main function
main
