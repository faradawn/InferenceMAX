#!/usr/bin/env bash
#
# Manual Sweep Scheduler - 1k1k
# Simplified version that mimics GitHub Actions workflow
#
# Usage: bash manual-sweep-1k1k-scheduler.sh
#

set -e

# ============================================================================
# Configuration
# ============================================================================

echo "============================================================================"
echo "Manual Sweep Scheduler - 1k1k"
echo "============================================================================"

# Workspace - current directory
export WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKSPACE_DIR"

# Results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
export RESULTS_BASE_DIR="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX"
export RESULTS_DIR="${RESULTS_BASE_DIR}/results_1k1k_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

# Environment variables (these are normally set by GitHub Actions)
export HF_TOKEN="${HF_TOKEN}"
export HF_HUB_CACHE="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export SLURM_ACCOUNT="coreai_prod_infbench"
export SLURM_PARTITION="batch"

# Verify HF_TOKEN is set
if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN environment variable is not set"
    echo "Please set it with: export HF_TOKEN='your_token'"
    exit 1
fi

echo "Workspace: ${WORKSPACE_DIR}"
echo "Results directory: ${RESULTS_DIR}"
echo ""

# ============================================================================
# Step 1: Generate Sweep Configs (using Python script like GitHub Actions)
# ============================================================================

echo "Step 1: Generating sweep configurations..."
echo "============================================================================"

# Install pydantic if needed
pip install -q pydantic 2>/dev/null || echo "pydantic already installed"

# Generate configs using the same script as GitHub Actions
# We'll create a temporary config file with our specific requirements
TEMP_CONFIG="${RESULTS_DIR}/temp_config.yaml"

cat > "${TEMP_CONFIG}" << 'EOF'
dsr1-fp4-b200-sglang:
  image: lmsysorg/sglang:v0.5.3rc1-cu129-b200
  model: nvidia/DeepSeek-R1-0528-FP4-V2
  model-prefix: dsr1
  runner: b200
  precision: fp4
  framework: sglang
  seq-len-configs:
  - isl: 1024
    osl: 1024
    search-space:
    - { tp: 4, conc-start: 4, conc-end: 4 }
    - { tp: 4, conc-start: 32, conc-end: 32 }
    - { tp: 4, conc-start: 128, conc-end: 128 }

dsr1-fp4-b200-trt:
  image: nvcr.io#nvidia/tensorrt-llm/release:1.1.0rc2.post2
  model: nvidia/DeepSeek-R1-0528-FP4-V2
  model-prefix: dsr1
  runner: b200
  precision: fp4
  framework: trt
  seq-len-configs:
  - isl: 1024
    osl: 1024
    search-space:
    - { tp: 4, conc-start: 4, conc-end: 4 }
    - { tp: 4, conc-start: 32, conc-end: 32 }
    - { tp: 4, ep: 4, conc-start: 128, conc-end: 128 }
EOF

# Generate JSON array of configurations
CONFIG_JSON=$(python3 utils/matrix-logic/generate_sweep_configs.py \
    full-sweep \
    --config-files "${TEMP_CONFIG}" \
    --seq-lens 1k1k \
    --model-prefix dsr1)

# Save the config JSON for reference
echo "$CONFIG_JSON" > "${RESULTS_DIR}/sweep_configs.json"

# Count configurations
CONFIG_COUNT=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
echo "Generated ${CONFIG_COUNT} benchmark configurations"
echo ""

# ============================================================================
# Step 2: Launch Benchmarks (loop through configs and call runner scripts)
# ============================================================================

echo "Step 2: Launching benchmarks..."
echo "============================================================================"

# Parse JSON and launch jobs
declare -a JOB_IDS
declare -a JOB_CONFIGS
JOB_INDEX=0

# Loop through each config in the JSON array
echo "$CONFIG_JSON" | python3 -c "
import sys, json
configs = json.load(sys.stdin)
for i, config in enumerate(configs):
    print(f'{i}:::{json.dumps(config)}')
" | while IFS=':::' read -r INDEX CONFIG; do
    
    # Parse the config JSON
    export IMAGE=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['image'])")
    export MODEL=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['model'])")
    export FRAMEWORK=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['framework'])")
    export PRECISION=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['precision'])")
    export RUNNER=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['runner'])")
    export ISL=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['isl'])")
    export OSL=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['osl'])")
    export TP=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['tp'])")
    export EP_SIZE=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['ep'])")
    export DP_ATTENTION=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['dp-attn'])")
    export CONC=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['conc'])")
    export MAX_MODEL_LEN=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['max-model-len'])")
    export EXP_NAME=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin)['exp-name'])")
    export RANDOM_RANGE_RATIO=0.8
    
    # Set additional environment variables
    export GITHUB_WORKSPACE="${WORKSPACE_DIR}"
    export RUNNER_TYPE="${RUNNER}"
    
    # Result filename (matches GitHub Actions format)
    export RESULT_FILENAME="${EXP_NAME}_${PRECISION}_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_dpa_${DP_ATTENTION}_conc${CONC}_${RUNNER}"
    
    # Job name
    JOB_NAME="bmk_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_conc${CONC}"
    
    echo ""
    echo "[$((INDEX + 1))/${CONFIG_COUNT}] Launching: ${JOB_NAME}"
    echo "  Framework: ${FRAMEWORK}, TP: ${TP}, EP: ${EP_SIZE}, DP_ATTN: ${DP_ATTENTION}, CONC: ${CONC}"
    
    # Create a wrapper script that calls the runner script
    WRAPPER_SCRIPT="${RESULTS_DIR}/run_${JOB_NAME}.sh"
    
    cat > "${WRAPPER_SCRIPT}" << 'EOF_WRAPPER'
#!/usr/bin/bash

# Export all environment variables
export HF_TOKEN="__HF_TOKEN__"
export HF_HUB_CACHE="__HF_HUB_CACHE__"
export IMAGE="__IMAGE__"
export MODEL="__MODEL__"
export FRAMEWORK="__FRAMEWORK__"
export PRECISION="__PRECISION__"
export RUNNER="__RUNNER__"
export ISL="__ISL__"
export OSL="__OSL__"
export TP="__TP__"
export EP_SIZE="__EP_SIZE__"
export DP_ATTENTION="__DP_ATTENTION__"
export CONC="__CONC__"
export MAX_MODEL_LEN="__MAX_MODEL_LEN__"
export EXP_NAME="__EXP_NAME__"
export RANDOM_RANGE_RATIO="__RANDOM_RANGE_RATIO__"
export RESULT_FILENAME="__RESULT_FILENAME__"
export GITHUB_WORKSPACE="__GITHUB_WORKSPACE__"
export RUNNER_TYPE="__RUNNER_TYPE__"

echo "============================================================================"
echo "Benchmark Job: __JOB_NAME__"
echo "============================================================================"
echo "SLURM_JOB_ID: $SLURM_JOB_ID"
echo "SLURMD_NODENAME: $SLURMD_NODENAME"
echo "Framework: $FRAMEWORK"
echo "Config: TP=$TP, EP=$EP_SIZE, DP_ATTN=$DP_ATTENTION, CONC=$CONC"
echo "============================================================================"

# Change to workspace directory
cd "$GITHUB_WORKSPACE"

# Call the runner script (this is what GitHub Actions does)
bash ./runners/launch_${RUNNER}-nv.sh

# Check if result was created
if [ -f "${RESULT_FILENAME}.json" ]; then
    echo ""
    echo "Processing result..."
    python3 utils/process_result.py
    
    # Copy result to results directory
    cp "agg_${RESULT_FILENAME}.json" "__RESULTS_DIR__/"
    echo "Result saved: __RESULTS_DIR__/agg_${RESULT_FILENAME}.json"
else
    echo "ERROR: Result file not found: ${RESULT_FILENAME}.json"
    exit 1
fi

echo "============================================================================"
echo "Benchmark completed successfully"
echo "============================================================================"
EOF_WRAPPER

    # Substitute environment variables
    sed -i "s|__HF_TOKEN__|${HF_TOKEN}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__HF_HUB_CACHE__|${HF_HUB_CACHE}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__IMAGE__|${IMAGE}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__MODEL__|${MODEL}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__FRAMEWORK__|${FRAMEWORK}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__PRECISION__|${PRECISION}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__RUNNER__|${RUNNER}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__ISL__|${ISL}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__OSL__|${OSL}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__TP__|${TP}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__EP_SIZE__|${EP_SIZE}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__DP_ATTENTION__|${DP_ATTENTION}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__CONC__|${CONC}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__MAX_MODEL_LEN__|${MAX_MODEL_LEN}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__EXP_NAME__|${EXP_NAME}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__RANDOM_RANGE_RATIO__|${RANDOM_RANGE_RATIO}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__RESULT_FILENAME__|${RESULT_FILENAME}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__GITHUB_WORKSPACE__|${GITHUB_WORKSPACE}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__RUNNER_TYPE__|${RUNNER_TYPE}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__RESULTS_DIR__|${RESULTS_DIR}|g" "${WRAPPER_SCRIPT}"
    sed -i "s|__JOB_NAME__|${JOB_NAME}|g" "${WRAPPER_SCRIPT}"
    
    chmod +x "${WRAPPER_SCRIPT}"
    
    # Submit job to Slurm
    SBATCH_OUTPUT=$(sbatch \
        --account="${SLURM_ACCOUNT}" \
        --partition="${SLURM_PARTITION}" \
        --nodes=1 \
        --exclusive \
        --time=03:00:00 \
        --job-name="${JOB_NAME}" \
        --output="${RESULTS_DIR}/${JOB_NAME}_%j.out" \
        --error="${RESULTS_DIR}/${JOB_NAME}_%j.err" \
        "${WRAPPER_SCRIPT}")
    
    JOB_ID=$(echo "$SBATCH_OUTPUT" | grep -oP '\d+')
    echo "  Job ID: ${JOB_ID}"
    
    # Save job info to a file for monitoring
    echo "${JOB_ID}|${JOB_NAME}|${RESULT_FILENAME}" >> "${RESULTS_DIR}/jobs.txt"
    
    # Small delay between submissions
    sleep 1
done

echo ""
echo "All jobs submitted!"
echo "============================================================================"

# ============================================================================
# Step 3: Monitor Jobs
# ============================================================================

echo ""
echo "Step 3: Monitoring job progress..."
echo "============================================================================"

# Function to check if a job is still running
is_job_running() {
    local JOB_ID=$1
    squeue -j "$JOB_ID" 2>/dev/null | grep -q "$JOB_ID"
}

echo "Waiting for all jobs to complete..."
echo ""

# Monitor jobs from the jobs.txt file
while true; do
    RUNNING_COUNT=0
    COMPLETED_COUNT=0
    FAILED_COUNT=0
    TOTAL_JOBS=0
    
    if [ -f "${RESULTS_DIR}/jobs.txt" ]; then
        while IFS='|' read -r JOB_ID JOB_NAME RESULT_FILENAME; do
            ((TOTAL_JOBS++))
            
            if is_job_running "$JOB_ID"; then
                ((RUNNING_COUNT++))
            else
                # Check if result exists
                if [ -f "${RESULTS_DIR}/agg_${RESULT_FILENAME}.json" ]; then
                    ((COMPLETED_COUNT++))
                else
                    ((FAILED_COUNT++))
                fi
            fi
        done < "${RESULTS_DIR}/jobs.txt"
    fi
    
    if [ "$TOTAL_JOBS" -eq 0 ]; then
        echo "No jobs found. Exiting."
        exit 1
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running: ${RUNNING_COUNT}, Completed: ${COMPLETED_COUNT}, Failed: ${FAILED_COUNT}, Total: ${TOTAL_JOBS}"
    
    # Check if all jobs are done
    if [ "$RUNNING_COUNT" -eq 0 ]; then
        echo ""
        echo "All jobs finished!"
        echo "  Completed: ${COMPLETED_COUNT}/${TOTAL_JOBS}"
        echo "  Failed: ${FAILED_COUNT}/${TOTAL_JOBS}"
        break
    fi
    
    sleep 30
done

# ============================================================================
# Step 4: Collect and Aggregate Results
# ============================================================================

echo ""
echo "Step 4: Collecting and aggregating results..."
echo "============================================================================"

cd "$WORKSPACE_DIR"

# Count result files
RESULT_COUNT=$(ls -1 "${RESULTS_DIR}"/agg_dsr1_*.json 2>/dev/null | wc -l)
echo "Found ${RESULT_COUNT} result files"

if [ "$RESULT_COUNT" -gt 0 ]; then
    # Run summarization
    echo ""
    echo "Generating summary..."
    python3 utils/summarize.py "${RESULTS_DIR}/" | tee "${RESULTS_DIR}/summary.txt"
    
    # Aggregate results
    echo ""
    echo "Aggregating results..."
    python3 utils/collect_results.py "${RESULTS_DIR}/" "dsr1_1k1k"
    
    # Move aggregated file to results directory
    if [ -f "agg_dsr1_1k1k.json" ]; then
        mv "agg_dsr1_1k1k.json" "${RESULTS_DIR}/"
        echo "Aggregated results: ${RESULTS_DIR}/agg_dsr1_1k1k.json"
    fi
else
    echo "WARNING: No result files found!"
    exit 1
fi

# ============================================================================
# Step 5: Generate Performance Plots
# ============================================================================

echo ""
echo "Step 5: Generating performance plots..."
echo "============================================================================"

pip install -q matplotlib 2>/dev/null || true

python3 utils/plot_perf.py "${RESULTS_DIR}/" "dsr1_1k1k"

# Move plots to results directory
if ls tput_vs_*.png 1> /dev/null 2>&1; then
    mv tput_vs_*.png "${RESULTS_DIR}/"
    echo "Performance plots saved to: ${RESULTS_DIR}/"
    ls -1 "${RESULTS_DIR}"/tput_vs_*.png
fi

# ============================================================================
# Final Summary
# ============================================================================

echo ""
echo "============================================================================"
echo "Sweep completed successfully!"
echo "============================================================================"
echo "Results directory: ${RESULTS_DIR}"
echo ""
echo "Generated files:"
echo "  - Individual results: ${RESULT_COUNT} JSON files"
echo "  - Aggregated results: agg_dsr1_1k1k.json"
echo "  - Summary: summary.txt"
echo "  - Plots: tput_vs_intvty_*.png, tput_vs_e2el_*.png"
echo ""
echo "To view results:"
echo "  cd ${RESULTS_DIR}"
echo "  cat summary.txt"
echo "  cat agg_dsr1_1k1k.json"
echo "============================================================================"
