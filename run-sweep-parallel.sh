#!/usr/bin/env bash
#
# Parallel Sweep Runner - Submits all jobs to Slurm queue at once
#
# Usage: bash run-sweep-parallel.sh <json_file>
#

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <json_config_file>"
    echo "Example: $0 envs/dsr1_1k1k_fp4_trtllm.json"
    exit 1
fi

JSON_FILE="$1"

if [ ! -f "$JSON_FILE" ]; then
    echo "ERROR: JSON file not found: $JSON_FILE"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed"
    exit 1
fi

if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN not set"
    exit 1
fi

# Setup
export WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
export RESULTS_DIR="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/parallel_results/run_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

export HF_HUB_CACHE="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export GITHUB_WORKSPACE="${WORKSPACE_DIR}"

CONFIG_COUNT=$(jq '. | length' "$JSON_FILE")

echo "Submitting ${CONFIG_COUNT} jobs to Slurm..."
echo ""

# Array to track job IDs
declare -a JOB_IDS

# Submit all jobs
for i in $(seq 0 $((CONFIG_COUNT - 1))); do
    CONFIG_INDEX=$((i + 1))
    
    # Extract config
    IMAGE=$(jq -r ".[$i].image" "$JSON_FILE")
    MODEL=$(jq -r ".[$i].model" "$JSON_FILE")
    FRAMEWORK=$(jq -r ".[$i].framework" "$JSON_FILE")
    PRECISION=$(jq -r ".[$i].precision" "$JSON_FILE")
    RUNNER="b200"
    ISL=$(jq -r ".[$i].isl" "$JSON_FILE")
    OSL=$(jq -r ".[$i].osl" "$JSON_FILE")
    TP=$(jq -r ".[$i].tp" "$JSON_FILE")
    EP_SIZE=$(jq -r ".[$i].ep" "$JSON_FILE")
    DP_ATTENTION=$(jq -r ".[$i][\"dp-attn\"]" "$JSON_FILE")
    CONC=$(jq -r ".[$i].conc" "$JSON_FILE")
    MAX_MODEL_LEN=$(jq -r ".[$i][\"max-model-len\"]" "$JSON_FILE")
    EXP_NAME=$(jq -r ".[$i][\"exp-name\"]" "$JSON_FILE")
    RESULT_FILENAME="${EXP_NAME}_${PRECISION}_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_dpa_${DP_ATTENTION}_conc${CONC}_${RUNNER}"
    
    JOB_NAME="bmk_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_conc${CONC}"
    
    # Create job script
    JOB_SCRIPT="${RESULTS_DIR}/job_${JOB_NAME}.sh"
    
    cat > "${JOB_SCRIPT}" << 'EOFSCRIPT'
#!/usr/bin/bash
#SBATCH --account=coreai_prod_infbench
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=01:00:00

# Disable command echoing for sensitive exports
set +x
export HF_TOKEN="__HF_TOKEN__"
export HF_HUB_CACHE="__HF_HUB_CACHE__"
set -x
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
export RANDOM_RANGE_RATIO=0.8
export RUNNER_TYPE="__RUNNER__"
export RESULT_FILENAME="__RESULT_FILENAME__"
export GITHUB_WORKSPACE="__WORKSPACE_DIR__"

cd "${GITHUB_WORKSPACE}"

# Run benchmark (we're already in allocated node via sbatch)
export HF_HUB_CACHE_MOUNT="${HF_HUB_CACHE}"
export MODEL_CODE="${EXP_NAME%%_*}"
export FRAMEWORK_SUFFIX=$([[ "$FRAMEWORK" == "trt" ]] && printf '_trt' || printf '')
export SQUASH_FILE="/lustre/fsw/coreai_prod_infbench/common/squash/$(echo "$IMAGE" | sed 's/[\/:@#]/_/g').sqsh"

# Import image if needed
if [ ! -f "$SQUASH_FILE" ]; then
    enroot import -o "$SQUASH_FILE" "docker://$IMAGE"
fi

# Determine benchmark script
if [[ "$FRAMEWORK" == "sglang" ]]; then
    BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200_docker.sh"
    export PORT=8888
    CONTAINER_MOUNTS="$GITHUB_WORKSPACE:/sgl-workspace,$HF_HUB_CACHE:$HF_HUB_CACHE"
    CONTAINER_WORKDIR="/sgl-workspace"
else
    BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200${FRAMEWORK_SUFFIX}_slurm.sh"
    CONTAINER_MOUNTS="$GITHUB_WORKSPACE:/workspace,$HF_HUB_CACHE:$HF_HUB_CACHE"
    CONTAINER_WORKDIR="/workspace"
fi

# Run benchmark
srun \
--container-image="$SQUASH_FILE" \
--container-name="infmax_${SLURM_JOB_ID}" \
--container-mounts="$CONTAINER_MOUNTS" \
--no-container-mount-home --container-writable \
--container-workdir="$CONTAINER_WORKDIR" \
--no-container-entrypoint --export=ALL \
bash "$BENCHMARK_SCRIPT"

# Save raw benchmark result
if [ -f "${RESULT_FILENAME}.json" ]; then
    cp "${RESULT_FILENAME}.json" "__RESULTS_DIR__/"
fi

# Process result (adds metadata)
python3 utils/process_result.py

# Save processed result
if [ -f "agg_${RESULT_FILENAME}.json" ]; then
    mv "agg_${RESULT_FILENAME}.json" "__RESULTS_DIR__/"
fi
EOFSCRIPT

    # Substitute variables
    sed -i "s|__HF_TOKEN__|${HF_TOKEN}|g" "${JOB_SCRIPT}"
    sed -i "s|__HF_HUB_CACHE__|${HF_HUB_CACHE}|g" "${JOB_SCRIPT}"
    sed -i "s|__IMAGE__|${IMAGE}|g" "${JOB_SCRIPT}"
    sed -i "s|__MODEL__|${MODEL}|g" "${JOB_SCRIPT}"
    sed -i "s|__FRAMEWORK__|${FRAMEWORK}|g" "${JOB_SCRIPT}"
    sed -i "s|__PRECISION__|${PRECISION}|g" "${JOB_SCRIPT}"
    sed -i "s|__RUNNER__|${RUNNER}|g" "${JOB_SCRIPT}"
    sed -i "s|__ISL__|${ISL}|g" "${JOB_SCRIPT}"
    sed -i "s|__OSL__|${OSL}|g" "${JOB_SCRIPT}"
    sed -i "s|__TP__|${TP}|g" "${JOB_SCRIPT}"
    sed -i "s|__EP_SIZE__|${EP_SIZE}|g" "${JOB_SCRIPT}"
    sed -i "s|__DP_ATTENTION__|${DP_ATTENTION}|g" "${JOB_SCRIPT}"
    sed -i "s|__CONC__|${CONC}|g" "${JOB_SCRIPT}"
    sed -i "s|__MAX_MODEL_LEN__|${MAX_MODEL_LEN}|g" "${JOB_SCRIPT}"
    sed -i "s|__EXP_NAME__|${EXP_NAME}|g" "${JOB_SCRIPT}"
    sed -i "s|__RESULT_FILENAME__|${RESULT_FILENAME}|g" "${JOB_SCRIPT}"
    sed -i "s|__WORKSPACE_DIR__|${WORKSPACE_DIR}|g" "${JOB_SCRIPT}"
    sed -i "s|__RESULTS_DIR__|${RESULTS_DIR}|g" "${JOB_SCRIPT}"
    
    chmod +x "${JOB_SCRIPT}"
    
    # Submit job
    SBATCH_OUT=$(sbatch \
        --job-name="${JOB_NAME}" \
        --output="${RESULTS_DIR}/${JOB_NAME}_%j.out" \
        --error="${RESULTS_DIR}/${JOB_NAME}_%j.err" \
        "${JOB_SCRIPT}")
    
    JOB_ID=$(echo "$SBATCH_OUT" | grep -oP '\d+')
    JOB_IDS[$i]=$JOB_ID
    
    echo "[$CONFIG_INDEX/$CONFIG_COUNT] Submitted: ${JOB_NAME} (Job ID: ${JOB_ID})"
    
    # Save job info
    echo "${JOB_ID}|${RESULT_FILENAME}" >> "${RESULTS_DIR}/jobs.txt"
done

echo ""
echo "All ${CONFIG_COUNT} jobs submitted!"
echo ""
echo "Monitor with: squeue -u \$USER"
echo "Or: watch -n 10 squeue -u \$USER"
echo ""

# Wait for all jobs to complete
echo "Waiting for jobs to complete..."

while true; do
    RUNNING=0
    COMPLETED=0
    
    for JOB_ID in "${JOB_IDS[@]}"; do
        if squeue -j "$JOB_ID" 2>/dev/null | grep -q "$JOB_ID"; then
            ((RUNNING++))
        else
            ((COMPLETED++))
        fi
    done
    
    echo "[$(date '+%H:%M:%S')] Running: ${RUNNING}/${CONFIG_COUNT}, Completed: ${COMPLETED}/${CONFIG_COUNT}"
    
    if [ "$RUNNING" -eq 0 ]; then
        break
    fi
    
    sleep 30
done

echo ""
echo "All jobs completed!"
echo ""

# Aggregate results
echo "Doing results aggregation"
cd "${WORKSPACE_DIR}"
python3 utils/collect_results.py "${RESULTS_DIR}/" "${EXP_NAME}"
mv "agg_${EXP_NAME}.json" "${RESULTS_DIR}/" 2>/dev/null || true

# Generate plots
pip install -q matplotlib 2>/dev/null || true
python3 utils/plot_perf.py "${RESULTS_DIR}/" "${EXP_NAME}"
mv tput_vs_*.png "${RESULTS_DIR}/" 2>/dev/null || true

echo "Results: ${RESULTS_DIR}"
echo ""
ls -lh "${RESULTS_DIR}"/*.png 2>/dev/null || true

