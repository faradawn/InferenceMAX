# Usage: bash run-sweep-from-json.sh envs/dsr1_1k1k_fp4_trtllm.json

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

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed"
    echo "Please install it: module load jq  or  yum install jq"
    exit 1
fi

# Required environment variables
if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN not set"
    echo "Please run: export HF_TOKEN='your_token'"
    exit 1
fi

# Setup paths
export WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
export RESULTS_DIR="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_sequential/run_${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

# Environment
export HF_HUB_CACHE="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export GITHUB_WORKSPACE="${WORKSPACE_DIR}"

# Count configs using jq (like GitHub Actions fromJson)
CONFIG_COUNT=$(jq '. | length' "$JSON_FILE")

# Loop through each config
for i in $(seq 0 $((CONFIG_COUNT - 1))); do
    CONFIG_INDEX=$((i + 1))
    
    # Extract config at index i using jq (like matrix.config in GitHub Actions)
    export IMAGE=$(jq -r ".[$i].image" "$JSON_FILE")
    export MODEL=$(jq -r ".[$i].model" "$JSON_FILE")
    export FRAMEWORK=$(jq -r ".[$i].framework" "$JSON_FILE")
    export PRECISION=$(jq -r ".[$i].precision" "$JSON_FILE")
    export RUNNER="b200"
    export ISL=$(jq -r ".[$i].isl" "$JSON_FILE")
    export OSL=$(jq -r ".[$i].osl" "$JSON_FILE")
    export TP=$(jq -r ".[$i].tp" "$JSON_FILE")
    export EP_SIZE=$(jq -r ".[$i].ep" "$JSON_FILE")
    export DP_ATTENTION=$(jq -r ".[$i][\"dp-attn\"]" "$JSON_FILE")
    export CONC=$(jq -r ".[$i].conc" "$JSON_FILE")
    export MAX_MODEL_LEN=$(jq -r ".[$i][\"max-model-len\"]" "$JSON_FILE")
    export EXP_NAME=$(jq -r ".[$i][\"exp-name\"]" "$JSON_FILE")
    export RANDOM_RANGE_RATIO=0.8
    export RUNNER_TYPE="${RUNNER}"
    export RESULT_FILENAME="${EXP_NAME}_${PRECISION}_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_dpa_${DP_ATTENTION}_conc${CONC}_${RUNNER}"
    
    # Run the launch script in background
    cd "${WORKSPACE_DIR}"
    LOG_FILE="${RESULTS_DIR}/${RESULT_FILENAME}.log"
    bash ./runners/launch_${RUNNER}-nv.sh > "${LOG_FILE}" 2>&1 &
    
    echo "=== Launched job ${CONFIG_INDEX}/${CONFIG_COUNT}: ${LOG_FILE}"
    sleep 3
done

# Wait for all background jobs to complete
echo "Waiting for all benchmarks to complete..."
wait

echo "All benchmarks completed. Results: ${RESULTS_DIR}"
