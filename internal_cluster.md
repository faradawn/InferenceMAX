# Internal Cluster Guide

```
cd /lustre/fsw/coreai_prod_infbench/faradawny/
source 
git clone https://github.com/faradawn/InferenceMAX.git
export HF_HOME="/lustre/fsw/coreai_prod_infbench/common/cache/"
hf download nvidia/DeepSeek-R1-0528-FP4-V2
hf download deepseek-ai/DeepSeek-R1-0528
```


# Running the script

```
source .venv/bin/activate

python3 utils/matrix-logic/generate_sweep_configs.py test-config --key dsr1-fp4-b200-trt --seq-len 1k1k --config-files .github/configs/nvidia-master.yaml --runner-config .github/configs/runners.yaml


{"image": "lmsysorg/sglang:v0.5.3rc1-cu129-b200", "model": "nvidia/DeepSeek-R1-0528-FP4-V2", "precision": "fp4", "framework": "sglang", "runner": "b200", "isl": 1024, "osl": 1024, "tp": 4, "ep": 1, "dp-attn": false, "conc": 4, "max-model-len": 2048, "exp-name": "dsr1_1k1k"}




python3 utils/matrix-logic/generate_sweep_configs.py runner-sweep --runner-type b200 --model-prefix dsr1 --precision fp8 --config-files .github/configs/amd-master.yaml .github/configs/nvidia-master.yaml --runner-config .github/configs/runners.yaml



python3 utils/matrix-logic/generate_sweep_configs.py  full-sweep --framework trt --runner-type b200 --model-prefix deepseek --config-files .github/configs/nvidia-master.yaml --runner-config .github/configs/runners.yaml


```