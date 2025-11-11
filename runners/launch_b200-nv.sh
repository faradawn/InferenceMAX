#!/usr/bin/bash

# HuggingFace cache location on Lustre
export HF_HUB_CACHE_MOUNT="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export PORT_OFFSET=0  # Doesn't matter when --exclusive

export MODEL_CODE="${EXP_NAME%%_*}"
export FRAMEWORK_SUFFIX=$([[ "$FRAMEWORK" == "trt" ]] && printf '_trt' || printf '')

export PARTITION="batch"
export SQUASH_FILE="/lustre/fsw/coreai_prod_infbench/common/squash/$(echo "$IMAGE" | sed 's/[\/:@#]/_/g').sqsh"
export SRUN_ARGS="-A coreai_prod_infbench -N1 --partition=$PARTITION --exclusive --time=01:00:00"

set -x

# Import Docker image to squash file if it doesn't exist
if [ ! -f "$SQUASH_FILE" ]; then
    srun $SRUN_ARGS bash -c "enroot import -o $SQUASH_FILE docker://$IMAGE"
fi

# Determine which benchmark script to run based on framework
if [[ "$FRAMEWORK" == "sglang" ]]; then
    BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200_docker.sh"
else
    BENCHMARK_SCRIPT="benchmarks/${MODEL_CODE}_${PRECISION}_b200${FRAMEWORK_SUFFIX}_slurm.sh"
fi

srun $SRUN_ARGS \
--container-image=$SQUASH_FILE \
--container-name=infmax \
--container-mounts=$GITHUB_WORKSPACE:/workspace/,$HF_HUB_CACHE_MOUNT:$HF_HUB_CACHE \
--no-container-mount-home --container-writable \
--container-workdir=/workspace/ \
--no-container-entrypoint --export=ALL \
bash $BENCHMARK_SCRIPT
