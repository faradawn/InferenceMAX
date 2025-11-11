#!/usr/bin/env bash

echo "Inside benchmarking dsr1_fp4_b200_docker.sh"

# To improve CI stability, we patch this helper function to prevent a race condition that
# happens 1% of the time. ref: https://github.com/flashinfer-ai/flashinfer/pull/1779
sed -i '102,108d' /usr/local/lib/python3.12/dist-packages/flashinfer/jit/cubin_loader.py

export PORT=8888

# Default: recv every ~10 requests; if CONC ≥ 16, relax to ~30 requests between scheduler recv polls.
if [[ $CONC -ge 16 ]]; then
  SCHEDULER_RECV_INTERVAL=30
else
  SCHEDULER_RECV_INTERVAL=10
fi
echo "SCHEDULER_RECV_INTERVAL: $SCHEDULER_RECV_INTERVAL, CONC: $CONC, ISL: $ISL, OSL: $OSL"

set -x
PYTHONNOUSERSITE=1 python3 -m sglang.launch_server --model-path $MODEL --host 0.0.0.0 --port $PORT --trust-remote-code \
--tensor-parallel-size=$TP --data-parallel-size=1 \
--cuda-graph-max-bs 256 --max-running-requests 256 --mem-fraction-static 0.85 --kv-cache-dtype fp8_e4m3 \
--chunked-prefill-size 16384 \
--enable-ep-moe --quantization modelopt_fp4 --enable-flashinfer-allreduce-fusion --scheduler-recv-interval $SCHEDULER_RECV_INTERVAL \
--enable-symm-mem --disable-radix-cache --attention-backend trtllm_mla --enable-flashinfer-trtllm-moe --stream-interval 10

# Prepare for benchmark
set +x
while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == *"The server is fired up and ready to roll!"* ]]; then
        break
    fi
done < <(tail -F -n0 "$SERVER_LOG")

git clone https://github.com/kimbochen/bench_serving.git
set -x
python3 bench_serving/benchmark_serving.py \
--model $MODEL --backend openai \
--base-url http://0.0.0.0:$PORT \
--dataset-name random \
--random-input-len $ISL --random-output-len $OSL --random-range-ratio $RANDOM_RANGE_RATIO \
--num-prompts $(( $CONC * 10 )) --max-concurrency $CONC \
--request-rate inf --ignore-eos \
--save-result --percentile-metrics 'ttft,tpot,itl,e2el' \
--result-dir /workspace/ \
--result-filename $RESULT_FILENAME.json
