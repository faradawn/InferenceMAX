# Simple Sweep Runner

**The simplest way to run benchmarks from a JSON config file.**

## Quick Start

```bash
# 1. Set your token
export HF_TOKEN="your_token_here"

# 2. Run the sweep
bash run-sweep-from-json.sh envs/dsr1_1k1k_fp4_trtllm.json
```

That's it! The script will:
1. Loop through each config in the JSON
2. Set environment variables
3. Call `runners/launch_b200-nv.sh` for each
4. Aggregate results and generate plots

## How It Works

```bash
# Read JSON file
for config in json_configs:
    # Set environment variables
    export IMAGE=$config[image]
    export MODEL=$config[model]
    export TP=$config[tp]
    export CONC=$config[conc]
    # ... etc
    
    # Run the launcher
    bash ./runners/launch_b200-nv.sh
    
    # Process result
    python3 utils/process_result.py
    mv result.json $RESULTS_DIR/

# After all done:
python3 utils/collect_results.py $RESULTS_DIR/
python3 utils/plot_perf.py $RESULTS_DIR/
```

## JSON Format

Your JSON file should be an array of config objects:

```json
[
  {
    "image": "nvcr.io#nvidia/tensorrt-llm/release:1.1.0rc2.post2",
    "model": "nvidia/DeepSeek-R1-0528-FP4-V2",
    "precision": "fp4",
    "framework": "trt",
    "runner": "b200-trt",
    "isl": 1024,
    "osl": 1024,
    "tp": 4,
    "ep": 1,
    "dp-attn": false,
    "conc": 4,
    "max-model-len": 2048,
    "exp-name": "dsr1_1k1k"
  },
  {
    "framework": "trt",
    "tp": 4,
    "conc": 32,
    ...
  }
]
```

## Generate JSON Config

You can generate JSON configs using the config generator:

```bash
# Generate TRT-LLM configs
python3 utils/matrix-logic/generate_sweep_configs.py \
    full-sweep \
    --config-files .github/configs/nvidia-master.yaml \
    --seq-lens 1k1k \
    --model-prefix dsr1 \
    --framework trt \
    > envs/my_configs.json

# Then run it
bash run-sweep-from-json.sh envs/my_configs.json
```

## Results

Results are saved to:
```
/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_<timestamp>/
├── agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200-trt.json
├── agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc32_b200-trt.json
├── ...
├── agg_dsr1_1k1k.json           # Aggregated
├── tput_vs_intvty_dsr1_1k1k.png # Plot 1
└── tput_vs_e2el_dsr1_1k1k.png   # Plot 2
```

## Examples

### Run a subset of configs

```bash
# Extract first 3 configs
python3 -c "import json; configs=json.load(open('envs/dsr1_1k1k_fp4_trtllm.json')); json.dump(configs[:3], open('test.json','w'))"

# Run just those 3
bash run-sweep-from-json.sh test.json
```

### Modify configs

```bash
# Change all TP to 8
python3 -c "
import json
configs = json.load(open('envs/dsr1_1k1k_fp4_trtllm.json'))
for c in configs:
    c['tp'] = 8
json.dump(configs, open('tp8_configs.json', 'w'))
"

bash run-sweep-from-json.sh tp8_configs.json
```

## Troubleshooting

### Script fails on first config
- Check: `export HF_TOKEN` is set
- Check: You have access to the runner (b200-nv)
- Check: The launcher script exists: `runners/launch_b200-nv.sh`

### Result file not found
- Look at the Slurm output for errors
- Check if the benchmark script ran successfully
- The result should be at: `<workspace>/${RESULT_FILENAME}.json`

### Can't find plots
- Check if matplotlib is installed: `pip install matplotlib`
- Check if result files are in the results directory
- Run manually: `python3 utils/plot_perf.py <results_dir>/ dsr1_1k1k`

## Advantages

✅ **Simple**: Just 130 lines  
✅ **No config generation**: Use pre-made JSON  
✅ **Sequential**: Runs one at a time (easy to debug)  
✅ **Reuses everything**: Calls existing runner scripts  
✅ **Complete**: Includes aggregation and plotting  

## When to Use

- **Quick tests**: Run a few configs manually
- **Debugging**: Test one config at a time
- **Custom configs**: Pre-generate JSON exactly how you want
- **Learning**: Understand the flow step-by-step

For production sweeps with many configs, consider using Slurm's job submission (`sbatch`) to run configs in parallel.

