# Internal Cluster Guide

```
cd /lustre/fsw/coreai_prod_infbench/faradawny/
source 
git clone https://github.com/faradawn/InferenceMAX.git
export HF_HOME="/lustre/fsw/coreai_prod_infbench/common/cache/"
hf download nvidia/DeepSeek-R1-0528-FP4-V2
hf download deepseek-ai/DeepSeek-R1-0528

mkdir -p  /lustre/fsw/coreai_prod_infbench/common/squash


# Running the scripts 
export HF_TOKEN=""
source env_dsr1_1k1k_tp4.sh
bash runners/launch_b200-nv.sh 


srun --jobid=$JOB_ID \
--containe  r-image=$SQUASH_FILE \
--container-mounts=$GITHUB_WORKSPACE:/workspace/,$HF_HUB_CACHE_MOUNT:$HF_HUB_CACHE \
--no-container-mount-home --container-writable \
--container-workdir=/workspace/ \
--overlap --export=ALL \
--pty bash

# manual
bash benchmarks/dsr1_fp4_b200_trt_slurm.sh 

# result
============ Serving Benchmark Result ============
Successful requests:                     40        
Benchmark duration (s):                  86.09     
Total input tokens:                      40960     
Total generated tokens:                  40920     
Request throughput (req/s):              0.46      
Output token throughput (tok/s):         475.31    
Total Token throughput (tok/s):          951.09    
---------------Time to First Token----------------
Mean TTFT (ms):                          191.22    
Median TTFT (ms):                        218.15    
P99 TTFT (ms):                           293.56    
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          8.24      
Median TPOT (ms):                        8.23      
P99 TPOT (ms):                           8.34      
---------------Inter-token Latency----------------
Mean ITL (ms):                           81.71     
Median ITL (ms):                         81.50     
P99 ITL (ms):                            82.55     
----------------End-to-end Latency----------------
Mean E2EL (ms):                          8607.65   
Median E2EL (ms):                        8606.41   
P99 E2EL (ms):                           8718.52   
==================================================
```


# Running the script

```
source .venv/bin/activate

python3 utils/matrix-logic/generate_sweep_configs.py test-config --key dsr1-fp4-b200-trt --seq-len 1k1k --config-files .github/configs/nvidia-master.yaml --runner-config .github/configs/runners.yaml


{"image": "lmsysorg/sglang:v0.5.3rc1-cu129-b200", "model": "nvidia/DeepSeek-R1-0528-FP4-V2", "precision": "fp4", "framework": "sglang", "runner": "b200", "isl": 1024, "osl": 1024, "tp": 4, "ep": 1, "dp-attn": false, "conc": 4, "max-model-len": 2048, "exp-name": "dsr1_1k1k"}




python3 utils/matrix-logic/generate_sweep_configs.py runner-sweep --runner-type b200 --model-prefix dsr1 --precision fp8 --config-files .github/configs/amd-master.yaml .github/configs/nvidia-master.yaml --runner-config .github/configs/runners.yaml



python3 utils/matrix-logic/generate_sweep_configs.py  full-sweep --framework trt --runner-type b200 --model-prefix deepseek --config-files .github/configs/nvidia-master.yaml --runner-config .github/configs/runners.yaml


```

