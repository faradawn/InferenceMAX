#!/usr/bin/env bash

# Configuration from JSON
export IMAGE="nvcr.io#nvidia/tensorrt-llm/release:1.1.0rc2.post2"
export MODEL="nvidia/DeepSeek-R1-0528-FP4-V2"
export PRECISION="fp4"
export FRAMEWORK="trt"
export EXP_NAME="dsr1_1k1k"

# Sequence length configuration
export ISL=1024
export OSL=1024
export MAX_MODEL_LEN=2048

# Parallelism configuration
export TP=4
export EP_SIZE=1
export DP_ATTENTION=false

# Concurrency configuration
export CONC=4

# Additional required variables
export RANDOM_RANGE_RATIO=1.0
export PORT_OFFSET=0

# Result filename
export RESULT_FILENAME="dsr1_fp4_b200_trt_1k1k_tp4_ep1_conc4"

# Cluster-specific paths (update these for your cluster)
export HF_HUB_CACHE_MOUNT="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export HF_HUB_CACHE="/lustre/fsw/coreai_prod_infbench/common/cache/"
export GITHUB_WORKSPACE="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX"

# HuggingFace token (set your actual token here or source from another file)
# export HF_TOKEN="your_token_here"

echo "Environment variables set for DeepSeek R1 FP4 on B200 with TRT-LLM"
echo "================================================"
echo "Model: $MODEL"
echo "Image: $IMAGE"
echo "ISL: $ISL, OSL: $OSL, MAX_MODEL_LEN: $MAX_MODEL_LEN"
echo "TP: $TP, EP: $EP_SIZE, DP_ATTENTION: $DP_ATTENTION, CONC: $CONC"
echo "Result file: $RESULT_FILENAME"
echo "================================================"

