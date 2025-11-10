#!/usr/bin/env bash
#
# Manual Sweep Scheduler - 1k1k
# Mimics the GitHub Actions workflow for running benchmarks manually on Slurm
#
# Usage: bash manual-sweep-1k1k-scheduler.sh
#

set -e

# ============================================================================
# Configuration
# ============================================================================

export SLURM_ACCOUNT="coreai_prod_infbench"
export SLURM_PARTITION="batch"
export HF_HUB_CACHE="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export HF_TOKEN="${HF_TOKEN}"  # Make sure this is set in your environment

# Results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
export RESULTS_BASE_DIR="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX"
export RESULTS_DIR="${RESULTS_BASE_DIR}/results_1k1k_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

# Workspace - current directory
export WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Experiment configuration
export EXP_NAME="dsr1_1k1k"
export MODEL_PREFIX="dsr1"
export PRECISION="fp4"
export ISL=1024
export OSL=1024
export MAX_MODEL_LEN=2048
export RANDOM_RANGE_RATIO=0.8

# Hardware configuration
export RUNNER_TYPE="b200"
export TP=4  # Tensor parallelism (single node, 4 GPUs)

# Concurrency sweep range
CONC_VALUES=(4 32 128)

# Frameworks to test
FRAMEWORKS=("sglang" "trt")

echo "============================================================================"
echo "Manual Sweep Scheduler - 1k1k"
echo "============================================================================"
echo "Experiment: ${EXP_NAME}"
echo "Model: DeepSeek-R1 FP4"
echo "Hardware: B200 (TP=${TP})"
echo "Sequence lengths: ISL=${ISL}, OSL=${OSL}"
echo "Concurrency values: ${CONC_VALUES[@]}"
echo "Frameworks: ${FRAMEWORKS[@]}"
echo "Results directory: ${RESULTS_DIR}"
echo "============================================================================"

# ============================================================================
# Step 1: Generate Sweep Configs
# ============================================================================

echo ""
echo "Step 1: Generating sweep configurations..."
echo "============================================================================"

# Define configurations for each framework
declare -A SGLANG_CONFIGS
declare -A TRT_CONFIGS

# SGLang configuration
SGLANG_MODEL="nvidia/DeepSeek-R1-0528-FP4-V2"
SGLANG_IMAGE="lmsysorg/sglang:v0.5.3rc1-cu129-b200"

# TRT-LLM configuration
TRT_MODEL="nvidia/DeepSeek-R1-0528-FP4-V2"
TRT_IMAGE="nvcr.io#nvidia/tensorrt-llm/release:1.1.0rc2.post2"

# EP and DP_ATTENTION settings based on InferenceMAX configs for TP=4, 1k1k
# Reference: .github/configs/nvidia-master.yaml lines 36-41
declare -A EP_SETTINGS
declare -A DP_ATTN_SETTINGS

# For TP=4, 1k1k:
# CONC 4-32: EP=1, DP_ATTN=false
# CONC 64-128: EP=4, DP_ATTN=false
# CONC 256: EP=4, DP_ATTN=true
EP_SETTINGS[4]=1
DP_ATTN_SETTINGS[4]="false"
EP_SETTINGS[32]=1
DP_ATTN_SETTINGS[32]="false"
EP_SETTINGS[128]=4
DP_ATTN_SETTINGS[128]="false"

echo "Configurations generated:"
echo "  - SGLang: ${#CONC_VALUES[@]} configurations"
echo "  - TRT-LLM: ${#CONC_VALUES[@]} configurations"
echo "  Total: $(( ${#CONC_VALUES[@]} * 2 )) benchmarks to run"
echo ""

# ============================================================================
# Step 2: Launch Benchmarks
# ============================================================================

echo "Step 2: Launching benchmarks..."
echo "============================================================================"

# Track job status
declare -a JOB_IDS
declare -a JOB_NAMES
JOB_COUNTER=0

# Function to launch a single benchmark job
launch_benchmark() {
    local FRAMEWORK=$1
    local CONC=$2
    local MODEL=$3
    local IMAGE=$4
    local EP_SIZE=${5:-1}
    local DP_ATTENTION=${6:-false}
    
    local RESULT_FILENAME="${EXP_NAME}_${PRECISION}_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_dpa_${DP_ATTENTION}_conc${CONC}_${RUNNER_TYPE}"
    local JOB_NAME="bmk_${FRAMEWORK}_tp${TP}_conc${CONC}"
    
    echo ""
    echo "Launching: ${JOB_NAME}"
    echo "  Framework: ${FRAMEWORK}"
    echo "  Model: ${MODEL}"
    echo "  TP: ${TP}, EP: ${EP_SIZE}, DP_ATTN: ${DP_ATTENTION}, CONC: ${CONC}"
    
    # Create a temporary launch script for this specific job
    local LAUNCH_SCRIPT="${RESULTS_DIR}/launch_${JOB_NAME}.sh"
    
    cat > "${LAUNCH_SCRIPT}" << 'EOF_LAUNCH'
#!/usr/bin/bash

# Import environment variables
export HF_TOKEN="${HF_TOKEN}"
export HF_HUB_CACHE="${HF_HUB_CACHE}"
export HF_HUB_CACHE_MOUNT="${HF_HUB_CACHE}"
export EXP_NAME="${EXP_NAME}"
export MODEL="${MODEL}"
export IMAGE="${IMAGE}"
export FRAMEWORK="${FRAMEWORK}"
export PRECISION="${PRECISION}"
export ISL="${ISL}"
export OSL="${OSL}"
export MAX_MODEL_LEN="${MAX_MODEL_LEN}"
export RANDOM_RANGE_RATIO="${RANDOM_RANGE_RATIO}"
export TP="${TP}"
export EP_SIZE="${EP_SIZE}"
export DP_ATTENTION="${DP_ATTENTION}"
export CONC="${CONC}"
export RESULT_FILENAME="${RESULT_FILENAME}"
export GITHUB_WORKSPACE="${WORKSPACE_DIR}"
export RUNNER_TYPE="${RUNNER_TYPE}"
export PORT_OFFSET=0

# Derived variables
export MODEL_CODE="${EXP_NAME%%_*}"
export FRAMEWORK_SUFFIX=$([[ "$FRAMEWORK" == "trt" ]] && printf '_trt' || printf '')
export PARTITION="${SLURM_PARTITION}"
export SQUASH_FILE="/lustre/fsw/coreai_prod_infbench/common/squash/$(echo "$IMAGE" | sed 's/[\/:@#]/_/g').sqsh"

echo "============================================================================"
echo "Starting benchmark job"
echo "============================================================================"
echo "SLURM_JOB_ID: $SLURM_JOB_ID"
echo "SLURMD_NODENAME: $SLURMD_NODENAME"
echo "Framework: $FRAMEWORK"
echo "Model: $MODEL"
echo "TP: $TP, EP: $EP_SIZE, DP_ATTN: $DP_ATTENTION, CONC: $CONC"
echo "Result file: $RESULT_FILENAME.json"
echo "============================================================================"

# Create squash file from Docker image if it doesn't exist
if [ ! -f "$SQUASH_FILE" ]; then
    echo "Creating squash file: $SQUASH_FILE"
    enroot import -o "$SQUASH_FILE" "docker://$IMAGE"
else
    echo "Squash file already exists: $SQUASH_FILE"
fi

# Determine which benchmark script to run based on framework
if [[ "$FRAMEWORK" == "sglang" ]]; then
    BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200_docker.sh"
    export PORT=8888
    CONTAINER_MOUNTS="$GITHUB_WORKSPACE:/sgl-workspace,$HF_HUB_CACHE_MOUNT:$HF_HUB_CACHE"
    export CONTAINER_WORKDIR="/sgl-workspace"
else
    BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200${FRAMEWORK_SUFFIX}_slurm.sh"
    CONTAINER_MOUNTS="$GITHUB_WORKSPACE:/workspace,$HF_HUB_CACHE_MOUNT:$HF_HUB_CACHE"
    export CONTAINER_WORKDIR="/workspace"
fi

echo "Benchmark script: $BENCHMARK_SCRIPT"
echo "Container mounts: $CONTAINER_MOUNTS"

# Run the benchmark in the container
srun \
--container-image="$SQUASH_FILE" \
--container-name=infmax_${SLURM_JOB_ID} \
--container-mounts="$CONTAINER_MOUNTS" \
--no-container-mount-home --container-writable \
--container-workdir="$CONTAINER_WORKDIR" \
--no-container-entrypoint --export=ALL \
bash "$BENCHMARK_SCRIPT"

# Check if result file was created
if [ -f "${CONTAINER_WORKDIR}/${RESULT_FILENAME}.json" ]; then
    echo "Benchmark completed successfully: ${RESULT_FILENAME}.json"
    
    # Process result
    cd "$GITHUB_WORKSPACE"
    python3 utils/process_result.py
    
    # Copy processed result to results directory
    cp "agg_${RESULT_FILENAME}.json" "${RESULTS_DIR}/"
    echo "Result saved to: ${RESULTS_DIR}/agg_${RESULT_FILENAME}.json"
else
    echo "ERROR: Benchmark result not found: ${RESULT_FILENAME}.json"
    exit 1
fi

echo "============================================================================"
echo "Benchmark job completed"
echo "============================================================================"
EOF_LAUNCH

    # Substitute environment variables in the launch script
    sed -i "s|\${HF_TOKEN}|${HF_TOKEN}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${HF_HUB_CACHE}|${HF_HUB_CACHE}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${EXP_NAME}|${EXP_NAME}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${MODEL}|${MODEL}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${IMAGE}|${IMAGE}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${FRAMEWORK}|${FRAMEWORK}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${PRECISION}|${PRECISION}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${ISL}|${ISL}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${OSL}|${OSL}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${MAX_MODEL_LEN}|${MAX_MODEL_LEN}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${RANDOM_RANGE_RATIO}|${RANDOM_RANGE_RATIO}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${TP}|${TP}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${EP_SIZE}|${EP_SIZE}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${DP_ATTENTION}|${DP_ATTENTION}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${CONC}|${CONC}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${RESULT_FILENAME}|${RESULT_FILENAME}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${WORKSPACE_DIR}|${WORKSPACE_DIR}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${RUNNER_TYPE}|${RUNNER_TYPE}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${SLURM_PARTITION}|${SLURM_PARTITION}|g" "${LAUNCH_SCRIPT}"
    sed -i "s|\${RESULTS_DIR}|${RESULTS_DIR}|g" "${LAUNCH_SCRIPT}"
    
    chmod +x "${LAUNCH_SCRIPT}"
    
    # Submit the job to Slurm
    SBATCH_OUTPUT=$(sbatch \
        --account="${SLURM_ACCOUNT}" \
        --partition="${SLURM_PARTITION}" \
        --nodes=1 \
        --gres=gpu:${TP} \
        --exclusive \
        --time=03:00:00 \
        --job-name="${JOB_NAME}" \
        --output="${RESULTS_DIR}/${JOB_NAME}_%j.out" \
        --error="${RESULTS_DIR}/${JOB_NAME}_%j.err" \
        "${LAUNCH_SCRIPT}")
    
    # Extract job ID
    local JOB_ID=$(echo "$SBATCH_OUTPUT" | grep -oP '\d+')
    
    echo "  Submitted job: ${JOB_ID}"
    echo "  Log file: ${RESULTS_DIR}/${JOB_NAME}_${JOB_ID}.out"
    
    # Track the job
    JOB_IDS[$JOB_COUNTER]=$JOB_ID
    JOB_NAMES[$JOB_COUNTER]="${JOB_NAME}"
    ((JOB_COUNTER++))
    
    # Small delay between submissions
    sleep 2
}

# Launch SGLang benchmarks
echo ""
echo "Launching SGLang benchmarks..."
echo "----------------------------------------------------------------------------"
for CONC in "${CONC_VALUES[@]}"; do
    launch_benchmark "sglang" "$CONC" "$SGLANG_MODEL" "$SGLANG_IMAGE" 1 "false"
done

# Launch TRT-LLM benchmarks
echo ""
echo "Launching TRT-LLM benchmarks..."
echo "----------------------------------------------------------------------------"
for CONC in "${CONC_VALUES[@]}"; do
    EP_SIZE=${EP_SETTINGS[$CONC]}
    DP_ATTN=${DP_ATTN_SETTINGS[$CONC]}
    launch_benchmark "trt" "$CONC" "$TRT_MODEL" "$TRT_IMAGE" "$EP_SIZE" "$DP_ATTN"
done

echo ""
echo "============================================================================"
echo "All benchmarks submitted!"
echo "Total jobs: ${#JOB_IDS[@]}"
echo "============================================================================"

# Display job summary
echo ""
echo "Job Summary:"
echo "----------------------------------------------------------------------------"
for i in "${!JOB_IDS[@]}"; do
    echo "  [${i}] Job ID: ${JOB_IDS[$i]} - ${JOB_NAMES[$i]}"
done

# ============================================================================
# Step 3: Monitor Jobs
# ============================================================================

echo ""
echo "Step 3: Monitoring job progress..."
echo "============================================================================"
echo "Waiting for all jobs to complete..."
echo ""

# Function to check if a job is still running
is_job_running() {
    local JOB_ID=$1
    squeue -j "$JOB_ID" 2>/dev/null | grep -q "$JOB_ID"
}

# Monitor jobs
while true; do
    RUNNING_COUNT=0
    COMPLETED_COUNT=0
    FAILED_COUNT=0
    
    for i in "${!JOB_IDS[@]}"; do
        JOB_ID=${JOB_IDS[$i]}
        JOB_NAME=${JOB_NAMES[$i]}
        
        if is_job_running "$JOB_ID"; then
            ((RUNNING_COUNT++))
        else
            # Check if job completed successfully
            RESULT_FILE=$(ls -t "${RESULTS_DIR}"/agg_*"${JOB_NAME#bmk_}"*.json 2>/dev/null | head -n1)
            if [ -n "$RESULT_FILE" ]; then
                ((COMPLETED_COUNT++))
            else
                ((FAILED_COUNT++))
            fi
        fi
    done
    
    TOTAL_JOBS=${#JOB_IDS[@]}
    PROCESSED=$((COMPLETED_COUNT + FAILED_COUNT))
    
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
RESULT_COUNT=$(ls -1 "${RESULTS_DIR}"/agg_*.json 2>/dev/null | wc -l)
echo "Found ${RESULT_COUNT} result files"

if [ "$RESULT_COUNT" -gt 0 ]; then
    # Run summarization
    echo ""
    echo "Generating summary..."
    python3 utils/summarize.py "${RESULTS_DIR}/" | tee "${RESULTS_DIR}/summary.txt"
    
    # Aggregate results
    echo ""
    echo "Aggregating results..."
    python3 utils/collect_results.py "${RESULTS_DIR}/" "${EXP_NAME}"
    
    # Move aggregated file to results directory
    if [ -f "agg_${EXP_NAME}.json" ]; then
        mv "agg_${EXP_NAME}.json" "${RESULTS_DIR}/"
        echo "Aggregated results saved to: ${RESULTS_DIR}/agg_${EXP_NAME}.json"
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

pip install -q matplotlib 2>/dev/null || echo "matplotlib already installed"

python3 utils/plot_perf.py "${RESULTS_DIR}/" "${EXP_NAME}"

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
echo "  - Aggregated results: agg_${EXP_NAME}.json"
echo "  - Summary: summary.txt"
echo "  - Plots: tput_vs_intvty_*.png, tput_vs_e2el_*.png"
echo ""
echo "To view results:"
echo "  cd ${RESULTS_DIR}"
echo "  ls -lh"
echo "============================================================================"

