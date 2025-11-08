#!/bin/bash
# export HF_HOME="/lustre/fsw/coreai_prod_infbench/common/cache/"
export HF_HOME="/lustre/fsw/coreai_prod_infbench/$USER/cache/huggingface"
cluster=`hostname | sed -n 's/^\([^0-9]*\).*/\1/p' | sed 's/^[^-]*-//'`
export CLUSTER=${cluster}
default_partition='batch'
if [[ ${CLUSTER} == "lyris" ]]; then
    default_partition='gb200'
fi
# options: x86_64, aarch64
cpu_arch=`uname -m`

launch-vllm() {
    partition=${default_partition}
    if ! [ -z "$1" ]; then
	    partition="$1"
    fi
    echo "Launcing vllm on ${partition}..."
    # Change to nightly? Maybe as cli argument?
    srun -A coreai_prod_infbench -N1 -p ${partition} \
        --mpi=pmix \
        --job-name=coreai_prod_infbench-vllm.bench \
        --container-image=vllm/vllm-openai:latest \
        --ntasks-per-node=1 \
        -t 04:00:00 \
        --container-name=vllm \
        --container-mounts=/lustre/fsw/coreai_prod_infbench/$USER:/mnt/$USER,/lustre/fsw/coreai_prod_infbench/$USER/.cache:/root/.cache,/lustre/fsw/coreai_prod_infbench/$USER/cache/huggingface/:/lustre/fsw/coreai_prod_infbench/$USER/cache/huggingface/,/lustre/fsw/coreai_prod_infbench/$USER/.scripts/:/vllm-workspace/.scripts,$pwd:/vllm-workspace/inference_max \
        --pty bash
}
launch-sglang() {
    partition=${default_partition}
    if ! [ -z "$1" ]; then
	    partition="$1"
    fi
    if [[ ${CLUSTER} == 'prenyx' ]]; then
        image=lmsysorg/sglang:v0.5.3rc1-cu129-b200
    elif [[ $partition == *gb200* || ${CLUSTER} == 'ptyche' ]]; then
        image=lmsysorg/sglang:v0.5.3-cu129-gb200
    else
        image=lmsysorg/sglang:latest
    fi
    echo "Launcing sglang on ${partition}..."
    echo "Using: ${image}"
    srun -A coreai_prod_infbench -N1 -p ${partition} \
        --mpi=pmix \
        --job-name=coreai_prod_infbench-sglang.bench \
        --container-image=${image} \
        --ntasks-per-node=1 \
        -t 04:00:00 \
        --container-name=sglang \
        --container-mounts=/lustre/fsw/coreai_prod_infbench/$USER:/mnt/$USER,/lustre/fsw/coreai_prod_infbench/$USER/.cache:/root/.cache,/lustre/fsw/coreai_prod_infbench/$USER/cache/huggingface/:/lustre/fsw/coreai_prod_infbench/$USER/cache/huggingface/,/lustre/fsw/coreai_prod_infbench/$USER/.scripts/:/sgl-workspace/sglang/.scripts,$pwd:/sgl-workspace/sglang/inference_max \
        --pty bash
}
launch() {
    local OPTIND # Reset OPTIND for each function call
	local framework=sglang
	local partition=""
	while getopts "f:p:" opt; do
    		case "${opt}" in
      			f)
                    framework=$OPTARG
                    ;;
				p)
                    partition=$OPTARG
                    ;;
      			*)
        			echo "Usage: unmount-lustre [-f] [-c <cluster>]" >&2
        			return 1
        			;;
    		esac
  	done

    if [[ ${framework} == 'vllm' ]]; then
        launch-vllm $partition
    elif [[ ${framework} == 'sglang' ]]; then
        launch-sglang $partition
    else
        echo "Unrecognized framework: ${framework}"
    fi
}

launch $@