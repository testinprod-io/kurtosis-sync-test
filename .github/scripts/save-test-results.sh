#!/bin/bash
set -e

# Script to save test results to the data branch
# Usage: ./save-test-results.sh

echo "Saving test results to data branch..."

# Check if required environment variables are set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable is required"
    exit 1
fi

# Get test metadata
if [ ! -f "sync-test-results/metadata.json" ]; then
    echo "Error: sync-test-results/metadata.json not found"
    exit 1
fi

# Extract metadata
METADATA=$(cat sync-test-results/metadata.json)
NETWORK=$(echo "$METADATA" | jq -r '.network')
EL_CLIENT=$(echo "$METADATA" | jq -r '.el_client')
CL_CLIENT=$(echo "$METADATA" | jq -r '.cl_client')
TIMESTAMP=$(echo "$METADATA" | jq -r '.start_time')

# Generate date-based path
DATE=$(date -u +%Y-%m-%d)
TIME=$(date -u +%H-%M-%S)

# Create filename based on test parameters
FILENAME="${TIME}_${EL_CLIENT}_${CL_CLIENT}.json"
FILEPATH="results/${DATE}/${NETWORK}/${FILENAME}"

echo "Will save to: $FILEPATH"

# Configure git
git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

# Create a temporary directory for data branch work
TEMP_DIR=$(mktemp -d)
echo "Working in temporary directory: $TEMP_DIR"

# Clone only the data branch (or create it if it doesn't exist)
cd "$TEMP_DIR"
if git ls-remote --heads "https://github.com/${GITHUB_REPOSITORY}.git" data | grep -q data; then
    echo "Data branch exists, cloning..."
    git clone --branch data --single-branch --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" data-branch
else
    echo "Data branch doesn't exist, creating..."
    git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" data-branch
    cd data-branch
    git checkout --orphan data
    git rm -rf . 2>/dev/null || true
    echo "# Test Results Data Branch" > README.md
    echo "This branch stores test results in JSON format." >> README.md
    echo "Data is organized by date and network." >> README.md
    git add README.md
    git commit -m "Initialize data branch"
    cd ..
fi

cd data-branch

# Create directory structure
mkdir -p "$(dirname "$FILEPATH")"

# Enhanced metadata with additional test information
ENHANCED_METADATA=$(echo "$METADATA" | jq --arg workflow "$GITHUB_WORKFLOW" \
    --arg run_id "$GITHUB_RUN_ID" \
    --arg run_number "$GITHUB_RUN_NUMBER" \
    --arg sha "$GITHUB_SHA" \
    --arg ref "$GITHUB_REF" \
    --arg actor "$GITHUB_ACTOR" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '. + {
        github: {
            workflow: $workflow,
            run_id: $run_id,
            run_number: $run_number,
            sha: $sha,
            ref: $ref,
            actor: $actor
        },
        saved_at: $timestamp
    }')

# Save enhanced metadata
echo "$ENHANCED_METADATA" > "$FILEPATH"

# Update daily index for this network
INDEX_FILE="results/${DATE}/${NETWORK}/index.json"
if [ -f "$INDEX_FILE" ]; then
    # Append to existing index
    EXISTING=$(cat "$INDEX_FILE")
    echo "$EXISTING" | jq --arg file "$FILENAME" --argjson metadata "$ENHANCED_METADATA" \
        '.tests += [{filename: $file, metadata: $metadata}]' > "${INDEX_FILE}.tmp"
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
else
    # Create new index
    echo "$ENHANCED_METADATA" | jq --arg file "$FILENAME" \
        '{date: "'$DATE'", network: "'$NETWORK'", tests: [{filename: $file, metadata: .}]}' > "$INDEX_FILE"
fi

# Update root catalog
CATALOG_FILE="catalog.json"
if [ ! -f "$CATALOG_FILE" ]; then
    echo '{"last_updated": "", "dates": []}' > "$CATALOG_FILE"
fi

# Add this date/network to catalog if not already present
jq --arg date "$DATE" --arg network "$NETWORK" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .last_updated = $updated |
    if (.dates | map(select(.date == $date and .network == $network)) | length) == 0 then
        .dates += [{date: $date, network: $network}]
    else . end |
    .dates |= sort_by(.date) | reverse
' "$CATALOG_FILE" > "${CATALOG_FILE}.tmp"
mv "${CATALOG_FILE}.tmp" "$CATALOG_FILE"

# Commit and push
git add -A
git commit -m "Add test results for ${NETWORK}/${EL_CLIENT}-${CL_CLIENT} at ${DATE} ${TIME}" || {
    echo "No changes to commit"
    exit 0
}

# Push to data branch
git push origin data

echo "Successfully saved test results to data branch"
echo "Data available at: https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/data/${FILEPATH}"

# Cleanup
cd "$GITHUB_WORKSPACE"
rm -rf "$TEMP_DIR"