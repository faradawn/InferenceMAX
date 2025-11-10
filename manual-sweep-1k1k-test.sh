#!/usr/bin/env bash
#
# Manual Sweep Test Script - 1k1k
# Quick validation script that runs a single benchmark to test the setup
#
# Usage: bash manual-sweep-1k1k-test.sh
#

set -e

# ============================================================================
# Configuration
# ============================================================================

export SLURM_ACCOUNT="coreai_prod_infbench"
export SLURM_PARTITION="batch"
export HF_HUB_CACHE="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export HF_TOKEN="${HF_TOKEN}"  # Make sure this is set in your environment

# Check HF_TOKEN
if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN environment variable is not set"
    echo "Please set it with: export HF_TOKEN='your_token'"
    exit 1
fi

# Results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
export RESULTS_BASE_DIR="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX"
export RESULTS_DIR="${RESULTS_BASE_DIR}/test_1k1k_${TIMESTAMP}"
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

# Test configuration - just one job
TEST_FRAMEWORK="sglang"
TEST_CONC=4
TEST_MODEL="nvidia/DeepSeek-R1-0528-FP4-V2"
TEST_IMAGE="lmsysorg/sglang:v0.5.3rc1-cu129-b200"
TEST_EP=1
TEST_DP_ATTN="false"

echo "============================================================================"
echo "Manual Sweep Test Script - 1k1k"
echo "============================================================================"
echo "This script runs a SINGLE benchmark job to validate the setup"
echo ""
echo "Configuration:"
echo "  Framework: ${TEST_FRAMEWORK}"
echo "  Model: ${TEST_MODEL}"
echo "  Hardware: B200 (TP=${TP})"
echo "  Sequence lengths: ISL=${ISL}, OSL=${OSL}"
echo "  Concurrency: ${TEST_CONC}"
echo "  Results directory: ${RESULTS_DIR}"
echo "============================================================================"

# ============================================================================
# Launch Test Benchmark
# ============================================================================

RESULT_FILENAME="${EXP_NAME}_${PRECISION}_${TEST_FRAMEWORK}_tp${TP}_ep${TEST_EP}_dpa_${TEST_DP_ATTN}_conc${TEST_CONC}_${RUNNER_TYPE}"
JOB_NAME="test_${TEST_FRAMEWORK}_tp${TP}_conc${TEST_CONC}"

echo ""
echo "Creating launch script..."

# Create launch script
LAUNCH_SCRIPT="${RESULTS_DIR}/launch_${JOB_NAME}.sh"

cat > "${LAUNCH_SCRIPT}" << 'EOF_LAUNCH'
#!/usr/bin/bash

# Job info
echo "============================================================================"
echo "Test Benchmark Job"
echo "============================================================================"
echo "SLURM_JOB_ID: $SLURM_JOB_ID"
echo "SLURMD_NODENAME: $SLURMD_NODENAME"
echo "============================================================================"

# Environment
export HF_TOKEN="__HF_TOKEN__"
export HF_HUB_CACHE="__HF_HUB_CACHE__"
export HF_HUB_CACHE_MOUNT="__HF_HUB_CACHE__"
export EXP_NAME="__EXP_NAME__"
export MODEL="__MODEL__"
export IMAGE="__IMAGE__"
export FRAMEWORK="__FRAMEWORK__"
export PRECISION="__PRECISION__"
export ISL="__ISL__"
export OSL="__OSL__"
export MAX_MODEL_LEN="__MAX_MODEL_LEN__"
export RANDOM_RANGE_RATIO="__RANDOM_RANGE_RATIO__"
export TP="__TP__"
export EP_SIZE="__EP_SIZE__"
export DP_ATTENTION="__DP_ATTENTION__"
export CONC="__CONC__"
export RESULT_FILENAME="__RESULT_FILENAME__"
export GITHUB_WORKSPACE="__WORKSPACE_DIR__"
export RUNNER_TYPE="__RUNNER_TYPE__"
export PORT_OFFSET=0

# Derived variables
export MODEL_CODE="${EXP_NAME%%_*}"
export PARTITION="__SLURM_PARTITION__"
export SQUASH_FILE="/lustre/fsw/coreai_prod_infbench/common/squash/$(echo "$IMAGE" | sed 's/[\/:@#]/_/g').sqsh"

echo ""
echo "Configuration:"
echo "  Framework: $FRAMEWORK"
echo "  Model: $MODEL"
echo "  TP: $TP, EP: $EP_SIZE, DP_ATTN: $DP_ATTENTION, CONC: $CONC"
echo "  Result file: $RESULT_FILENAME.json"
echo ""

# Create squash file from Docker image if it doesn't exist
if [ ! -f "$SQUASH_FILE" ]; then
    echo "Creating squash file: $SQUASH_FILE"
    echo "This may take 5-10 minutes on first run..."
    enroot import -o "$SQUASH_FILE" "docker://$IMAGE"
    echo "Squash file created successfully"
else
    echo "Squash file already exists: $SQUASH_FILE"
fi

# Determine benchmark script and container settings
BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200_docker.sh"
export PORT=8888
CONTAINER_MOUNTS="$GITHUB_WORKSPACE:/sgl-workspace,$HF_HUB_CACHE_MOUNT:$HF_HUB_CACHE"
export CONTAINER_WORKDIR="/sgl-workspace"

echo ""
echo "Running benchmark..."
echo "  Benchmark script: $BENCHMARK_SCRIPT"
echo "  Container workdir: $CONTAINER_WORKDIR"
echo ""

# Run the benchmark in the container
srun \
--container-image="$SQUASH_FILE" \
--container-name=infmax_test_${SLURM_JOB_ID} \
--container-mounts="$CONTAINER_MOUNTS" \
--no-container-mount-home --container-writable \
--container-workdir="$CONTAINER_WORKDIR" \
--no-container-entrypoint --export=ALL \
bash "$BENCHMARK_SCRIPT"

# Check if result file was created
RESULT_FILE="${CONTAINER_WORKDIR}/${RESULT_FILENAME}.json"
if [ -f "$RESULT_FILE" ]; then
    echo ""
    echo "✓ Benchmark completed successfully!"
    echo "  Result file: ${RESULT_FILENAME}.json"
    
    # Process result
    echo ""
    echo "Processing result..."
    cd "$GITHUB_WORKSPACE"
    python3 utils/process_result.py
    
    # Copy processed result to results directory
    cp "agg_${RESULT_FILENAME}.json" "__RESULTS_DIR__/"
    echo ""
    echo "✓ Result processed and saved to: __RESULTS_DIR__/agg_${RESULT_FILENAME}.json"
    
    # Show result summary
    echo ""
    echo "Result Summary:"
    echo "----------------------------------------------------------------------------"
    python3 -c "import json; data = json.load(open('agg_${RESULT_FILENAME}.json')); print(f\"  Throughput per GPU: {data['tput_per_gpu']:.2f} tok/s\"); print(f\"  End-to-end Latency: {data.get('median_e2el', 0):.3f} s\"); print(f\"  Interactivity: {data.get('median_intvty', 0):.2f} tok/s/user\")"
    echo "----------------------------------------------------------------------------"
else
    echo ""
    echo "✗ ERROR: Benchmark result not found: ${RESULT_FILENAME}.json"
    echo "Check the container workdir: $CONTAINER_WORKDIR"
    exit 1
fi

echo ""
echo "============================================================================"
echo "Test completed successfully!"
echo "============================================================================"
EOF_LAUNCH

# Substitute variables in the launch script
sed -i "s|__HF_TOKEN__|${HF_TOKEN}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__HF_HUB_CACHE__|${HF_HUB_CACHE}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__EXP_NAME__|${EXP_NAME}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__MODEL__|${TEST_MODEL}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__IMAGE__|${TEST_IMAGE}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__FRAMEWORK__|${TEST_FRAMEWORK}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__PRECISION__|${PRECISION}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__ISL__|${ISL}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__OSL__|${OSL}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__MAX_MODEL_LEN__|${MAX_MODEL_LEN}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__RANDOM_RANGE_RATIO__|${RANDOM_RANGE_RATIO}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__TP__|${TP}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__EP_SIZE__|${TEST_EP}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__DP_ATTENTION__|${TEST_DP_ATTN}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__CONC__|${TEST_CONC}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__RESULT_FILENAME__|${RESULT_FILENAME}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__WORKSPACE_DIR__|${WORKSPACE_DIR}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__RUNNER_TYPE__|${RUNNER_TYPE}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__SLURM_PARTITION__|${SLURM_PARTITION}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__RESULTS_DIR__|${RESULTS_DIR}|g" "${LAUNCH_SCRIPT}"

chmod +x "${LAUNCH_SCRIPT}"

echo "✓ Launch script created: ${LAUNCH_SCRIPT}"
echo ""
echo "Submitting test job to Slurm..."

# Submit the job
SBATCH_OUTPUT=$(sbatch \
    --account="${SLURM_ACCOUNT}" \
    --partition="${SLURM_PARTITION}" \
    --nodes=1 \
    --gres=gpu:${TP} \
    --exclusive \
    --time=01:00:00 \
    --job-name="${JOB_NAME}" \
    --output="${RESULTS_DIR}/${JOB_NAME}_%j.out" \
    --error="${RESULTS_DIR}/${JOB_NAME}_%j.err" \
    "${LAUNCH_SCRIPT}")

# Extract job ID
JOB_ID=$(echo "$SBATCH_OUTPUT" | grep -oP '\d+')

echo "✓ Job submitted: ${JOB_ID}"
echo ""
echo "============================================================================"
echo "Monitoring job progress..."
echo "============================================================================"
echo ""
echo "You can monitor the job with:"
echo "  squeue -j ${JOB_ID}"
echo "  tail -f ${RESULTS_DIR}/${JOB_NAME}_${JOB_ID}.out"
echo ""

# Monitor the job
echo "Waiting for job to complete (timeout: 60 minutes)..."
TIMEOUT=3600  # 60 minutes
ELAPSED=0
POLL_INTERVAL=10

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if job is still in queue
    if ! squeue -j "$JOB_ID" 2>/dev/null | grep -q "$JOB_ID"; then
        echo ""
        echo "Job completed!"
        
        # Check if result file exists
        RESULT_FILE="${RESULTS_DIR}/agg_${RESULT_FILENAME}.json"
        if [ -f "$RESULT_FILE" ]; then
            echo ""
            echo "============================================================================"
            echo "✓ Test PASSED"
            echo "============================================================================"
            echo ""
            echo "Result file: ${RESULT_FILE}"
            echo ""
            echo "View the result:"
            echo "  cat ${RESULT_FILE}"
            echo ""
            echo "View job output:"
            echo "  cat ${RESULTS_DIR}/${JOB_NAME}_${JOB_ID}.out"
            echo ""
            echo "The full sweep script is ready to use:"
            echo "  bash ${WORKSPACE_DIR}/manual-sweep-1k1k-scheduler.sh"
            echo ""
            exit 0
        else
            echo ""
            echo "============================================================================"
            echo "✗ Test FAILED"
            echo "============================================================================"
            echo ""
            echo "Result file not found: ${RESULT_FILE}"
            echo ""
            echo "Check the job logs:"
            echo "  cat ${RESULTS_DIR}/${JOB_NAME}_${JOB_ID}.out"
            echo "  cat ${RESULTS_DIR}/${JOB_NAME}_${JOB_ID}.err"
            echo ""
            exit 1
        fi
    fi
    
    # Show progress
    if [ $(($ELAPSED % 60)) -eq 0 ]; then
        STATE=$(squeue -j "$JOB_ID" -h -o "%T" 2>/dev/null || echo "UNKNOWN")
        echo "[$(date '+%H:%M:%S')] Job ${JOB_ID} state: ${STATE} (elapsed: ${ELAPSED}s)"
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo ""
echo "✗ Test timeout after ${TIMEOUT} seconds"
echo "Job may still be running. Check manually:"
echo "  squeue -j ${JOB_ID}"
exit 1

