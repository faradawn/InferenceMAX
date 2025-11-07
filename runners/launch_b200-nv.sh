#!/usr/bin/bash

# HuggingFace cache location on Lustre
export HF_HUB_CACHE_MOUNT="/lustre/fsw/coreai_prod_infbench/common/cache/hub/"
export PORT_OFFSET=0  # Doesn't matter when --exclusive

MODEL_CODE="${EXP_NAME%%_*}"
FRAMEWORK_SUFFIX=$([[ "$FRAMEWORK" == "trt" ]] && printf '_trt' || printf '')

PARTITION="batch"
SQUASH_FILE="/lustre/fsw/coreai_prod_infbench/common/squash/$(echo "$IMAGE" | sed 's/[\/:@#]/_/g').sqsh"

salloc -A coreai_prod_infbench -N1 --partition=$PARTITION --exclusive --time=180 --no-shell
JOB_ID=$(squeue -u $USER -h -o %A | head -n1)

set -x
srun --jobid=$JOB_ID bash -c "enroot import -o $SQUASH_FILE docker://$IMAGE"
srun --jobid=$JOB_ID \
--container-image=$SQUASH_FILE \
--container-mounts=$GITHUB_WORKSPACE:/workspace/,$HF_HUB_CACHE_MOUNT:$HF_HUB_CACHE \
--no-container-mount-home --container-writable \
--container-workdir=/workspace/ \
--no-container-entrypoint --export=ALL \
bash benchmarks/${MODEL_CODE}_${PRECISION}_b200${FRAMEWORK_SUFFIX}_slurm.sh

scancel $JOB_ID
