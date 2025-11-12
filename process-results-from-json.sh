#!/bin/bash
# Usage: bash process-results-from-json.sh envs/dsr1_1k1k_fp4_trtllm.json
# Processes raw benchmark JSON files into aggregated summary files for plotting

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

# Count configs using jq
CONFIG_COUNT=$(jq '. | length' "$JSON_FILE")

echo "Processing ${CONFIG_COUNT} benchmark results..."
echo ""

# Loop through each config
for i in $(seq 0 $((CONFIG_COUNT - 1))); do
    CONFIG_INDEX=$((i + 1))
    
    # Extract config at index i using jq (same as run-sweep-from-json.sh)
    export FRAMEWORK=$(jq -r ".[$i].framework" "$JSON_FILE")
    export PRECISION=$(jq -r ".[$i].precision" "$JSON_FILE")
    export RUNNER=$(jq -r ".[$i].runner" "$JSON_FILE")
    export TP=$(jq -r ".[$i].tp" "$JSON_FILE")
    export EP_SIZE=$(jq -r ".[$i].ep" "$JSON_FILE")
    export DP_ATTENTION=$(jq -r ".[$i][\"dp-attn\"]" "$JSON_FILE")
    export CONC=$(jq -r ".[$i].conc" "$JSON_FILE")
    export EXP_NAME=$(jq -r ".[$i][\"exp-name\"]" "$JSON_FILE")
    export RUNNER_TYPE="${RUNNER}"
    export RESULT_FILENAME="${EXP_NAME}_${PRECISION}_${FRAMEWORK}_tp${TP}_ep${EP_SIZE}_dpa_${DP_ATTENTION}_conc${CONC}_${RUNNER}"
    
    # Check if raw JSON file exists
    if [ ! -f "${RESULT_FILENAME}.json" ]; then
        echo "[${CONFIG_INDEX}/${CONFIG_COUNT}] SKIP: ${RESULT_FILENAME}.json not found"
        continue
    fi
    
    # Process the result
    echo "[${CONFIG_INDEX}/${CONFIG_COUNT}] Processing: ${RESULT_FILENAME}.json"
    python3 utils/process_result.py
    
    # Verify output was created
    if [ -f "agg_${RESULT_FILENAME}.json" ]; then
        echo "[${CONFIG_INDEX}/${CONFIG_COUNT}] Created: agg_${RESULT_FILENAME}.json"
    else
        echo "[${CONFIG_INDEX}/${CONFIG_COUNT}] ERROR: Failed to create agg_${RESULT_FILENAME}.json"
    fi
    echo ""
done

echo "Processing complete!"
echo ""
echo "To create graphs, run:"
echo "  python3 utils/plot_perf.py . <exp_name>"
echo ""
echo "Example:"
echo "  python3 utils/plot_perf.py . dsr1_1k1k"

