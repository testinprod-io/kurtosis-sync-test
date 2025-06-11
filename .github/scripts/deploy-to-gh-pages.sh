#!/bin/bash
set -e

# Script to deploy test results to gh-pages branch while preserving history
# Usage: ./deploy-to-gh-pages.sh <run-id> <run-type> <report-path>

RUN_ID="${1}"
RUN_TYPE="${2:-sync-test}"  # sync-test or comprehensive
REPORT_PATH="${3:-./reports}"

if [ -z "$RUN_ID" ]; then
    echo "Error: Run ID is required"
    exit 1
fi

echo "Deploying test results to gh-pages branch..."
echo "Run ID: $RUN_ID"
echo "Run Type: $RUN_TYPE"
echo "Report Path: $REPORT_PATH"

# Configure git
git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

# Create a temporary directory for gh-pages work
TEMP_DIR=$(mktemp -d)
echo "Working in temporary directory: $TEMP_DIR"

# Clone the repository (just the gh-pages branch)
cd "$TEMP_DIR"
git clone --branch gh-pages --single-branch "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" gh-pages || {
    echo "gh-pages branch doesn't exist, creating it..."
    git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" gh-pages
    cd gh-pages
    git checkout --orphan gh-pages
    git rm -rf . || true
    echo "# GitHub Pages" > README.md
    git add README.md
    git commit -m "Initialize gh-pages branch"
    cd ..
}

cd gh-pages

# Create directory structure
mkdir -p "runs/${RUN_TYPE}/${RUN_ID}"

# Copy the report files
cp -r "${GITHUB_WORKSPACE}/${REPORT_PATH}"/* "runs/${RUN_TYPE}/${RUN_ID}/" || {
    echo "Warning: No report files found in ${REPORT_PATH}"
}

# Create metadata file for this run
cat > "runs/${RUN_TYPE}/${RUN_ID}/metadata.json" << EOF
{
  "run_id": "${RUN_ID}",
  "run_type": "${RUN_TYPE}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workflow_run": "${GITHUB_RUN_ID}",
  "workflow_name": "${GITHUB_WORKFLOW}",
  "commit_sha": "${GITHUB_SHA}",
  "ref": "${GITHUB_REF}",
  "actor": "${GITHUB_ACTOR}"
}
EOF

# Generate index.json with all runs
echo "Generating index.json..."
cat > index.json << 'EOF'
{
  "runs": [
EOF

first=true
for run_type_dir in runs/*; do
    if [ -d "$run_type_dir" ]; then
        run_type=$(basename "$run_type_dir")
        for run_dir in "$run_type_dir"/*; do
            if [ -d "$run_dir" ] && [ -f "$run_dir/metadata.json" ]; then
                if [ "$first" = true ]; then
                    first=false
                else
                    echo "," >> index.json
                fi
                # Extract metadata and add path info
                jq -c '. + {"path": "'"$run_dir"'"}' "$run_dir/metadata.json" >> index.json
            fi
        done
    fi
done

cat >> index.json << 'EOF'
  ]
}
EOF

# Generate main index.html
cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kurtosis Sync Test Results</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f6f8fa;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: white;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 30px;
            margin-bottom: 20px;
        }
        .header h1 {
            margin: 0;
            color: #24292e;
        }
        .header p {
            color: #586069;
            margin-top: 10px;
        }
        .filters {
            background: white;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 20px;
            margin-bottom: 20px;
        }
        .filters select, .filters input {
            padding: 8px;
            margin-right: 10px;
            border: 1px solid #e1e4e8;
            border-radius: 4px;
        }
        .runs-grid {
            display: grid;
            gap: 15px;
        }
        .run-card {
            background: white;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 20px;
            transition: transform 0.2s;
        }
        .run-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 3px 6px rgba(0,0,0,0.15);
        }
        .run-card h3 {
            margin: 0 0 10px 0;
            color: #0366d6;
        }
        .run-card a {
            text-decoration: none;
            color: inherit;
        }
        .run-metadata {
            display: grid;
            grid-template-columns: auto 1fr;
            gap: 10px;
            color: #586069;
            font-size: 14px;
        }
        .run-metadata dt {
            font-weight: 600;
        }
        .run-type {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            margin-bottom: 10px;
        }
        .run-type.comprehensive {
            background-color: #f3f4f6;
            color: #4b5563;
        }
        .run-type.sync-test {
            background-color: #e0f2fe;
            color: #075985;
        }
        .loading {
            text-align: center;
            padding: 40px;
            color: #586069;
        }
        .error {
            background-color: #ffeaea;
            color: #d73a49;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Kurtosis Sync Test Results</h1>
            <p>Historical test runs for Ethereum client synchronization testing</p>
        </div>
        
        <div class="filters">
            <select id="typeFilter">
                <option value="">All Types</option>
                <option value="comprehensive">Comprehensive</option>
                <option value="sync-test">Individual Tests</option>
            </select>
            <input type="date" id="dateFilter" placeholder="Filter by date">
            <input type="text" id="searchFilter" placeholder="Search runs...">
        </div>
        
        <div id="loading" class="loading">Loading test runs...</div>
        <div id="error" class="error" style="display: none;"></div>
        <div id="runs" class="runs-grid"></div>
    </div>

    <script>
        async function loadRuns() {
            const loadingEl = document.getElementById('loading');
            const errorEl = document.getElementById('error');
            const runsEl = document.getElementById('runs');
            
            try {
                const response = await fetch('index.json');
                const data = await response.json();
                
                loadingEl.style.display = 'none';
                displayRuns(data.runs);
                setupFilters(data.runs);
            } catch (error) {
                loadingEl.style.display = 'none';
                errorEl.style.display = 'block';
                errorEl.textContent = 'Error loading test runs: ' + error.message;
            }
        }
        
        function displayRuns(runs) {
            const runsEl = document.getElementById('runs');
            
            // Sort runs by timestamp (newest first)
            runs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
            
            runsEl.innerHTML = runs.map(run => `
                <div class="run-card">
                    <a href="${run.path}/index.html">
                        <span class="run-type ${run.run_type}">${run.run_type.replace('-', ' ')}</span>
                        <h3>Run #${run.workflow_run || run.run_id}</h3>
                        <dl class="run-metadata">
                            <dt>Date:</dt>
                            <dd>${new Date(run.timestamp).toLocaleString()}</dd>
                            <dt>Workflow:</dt>
                            <dd>${run.workflow_name || 'N/A'}</dd>
                            <dt>Actor:</dt>
                            <dd>${run.actor || 'N/A'}</dd>
                            <dt>Commit:</dt>
                            <dd>${run.commit_sha ? run.commit_sha.substring(0, 7) : 'N/A'}</dd>
                        </dl>
                    </a>
                </div>
            `).join('');
        }
        
        function setupFilters(runs) {
            const typeFilter = document.getElementById('typeFilter');
            const dateFilter = document.getElementById('dateFilter');
            const searchFilter = document.getElementById('searchFilter');
            
            function applyFilters() {
                const type = typeFilter.value;
                const date = dateFilter.value;
                const search = searchFilter.value.toLowerCase();
                
                const filtered = runs.filter(run => {
                    if (type && run.run_type !== type) return false;
                    if (date) {
                        const runDate = new Date(run.timestamp).toISOString().split('T')[0];
                        if (runDate !== date) return false;
                    }
                    if (search) {
                        const searchableText = [
                            run.run_id,
                            run.workflow_name,
                            run.actor,
                            run.commit_sha
                        ].join(' ').toLowerCase();
                        if (!searchableText.includes(search)) return false;
                    }
                    return true;
                });
                
                displayRuns(filtered);
            }
            
            typeFilter.addEventListener('change', applyFilters);
            dateFilter.addEventListener('change', applyFilters);
            searchFilter.addEventListener('input', applyFilters);
        }
        
        // Load runs on page load
        loadRuns();
    </script>
</body>
</html>
EOF

# Add all changes
git add -A

# Commit changes
git commit -m "Deploy test results for run ${RUN_ID}" || {
    echo "No changes to commit"
    exit 0
}

# Push to gh-pages branch
git push origin gh-pages

echo "Successfully deployed to gh-pages branch"
echo "Results available at: https://${GITHUB_REPOSITORY_OWNER}.github.io/${GITHUB_REPOSITORY#*/}/runs/${RUN_TYPE}/${RUN_ID}/"