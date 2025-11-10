# Manual Sweep - Quick Summary

## What the Script Does (5 Steps)

```bash
# 1. Generate JSON config array (like GitHub Actions)
python3 utils/matrix-logic/generate_sweep_configs.py full-sweep \
    --config-files temp_config.yaml --seq-lens 1k1k --model-prefix dsr1
# Output: [{"image": "...", "tp": 4, "conc": 4, ...}, {...}, ...]

# 2. Loop through array and submit Slurm jobs
for config in configs:
    export IMAGE=$config[image]
    export TP=$config[tp]
    export CONC=$config[conc]
    # ... 
    
    # Create wrapper that calls the runner script
    sbatch wrapper.sh  # Inside: bash ./runners/launch_b200-nv.sh

# 3. Monitor jobs until completion
while jobs_running:
    check_status()
    sleep 30

# 4. Collect results
python3 utils/collect_results.py results/ dsr1_1k1k

# 5. Generate plots
python3 utils/plot_perf.py results/ dsr1_1k1k
```

## Architecture Diagram

```
┌──────────────────────────────────────────────────┐
│ manual-sweep-1k1k-scheduler.sh                   │
└──────────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌─────────────────┐     ┌──────────────────┐
│ generate_sweep  │     │ For each config: │
│ _configs.py     │────▶│ Submit Slurm job │
│                 │     └──────────────────┘
│ Creates JSON    │               │
└─────────────────┘               │
                                  ▼
                    ┌──────────────────────────┐
                    │ Slurm Job (wrapper.sh)   │
                    └──────────────────────────┘
                                  │
                ┌─────────────────┴─────────────────┐
                ▼                                   ▼
    ┌───────────────────────┐         ┌───────────────────────┐
    │ runners/              │         │ benchmarks/           │
    │ launch_b200-nv.sh     │────────▶│ dsr1_fp4_b200_*.sh    │
    │                       │         │                       │
    │ - Allocate Slurm node │         │ - Start server        │
    │ - Import Docker image │         │ - Run benchmark       │
    │ - Launch container    │         │ - Save result.json    │
    └───────────────────────┘         └───────────────────────┘
                                                  │
                                                  ▼
                                      ┌───────────────────────┐
                                      │ utils/                │
                                      │ process_result.py     │
                                      │                       │
                                      │ - Add metadata        │
                                      │ - Save agg_*.json     │
                                      └───────────────────────┘
```

## Key Changes from Original Script

### ❌ Removed (Complex)
- Custom config generation with bash arrays
- Inline Slurm job script creation
- Manual container launch logic
- `--gres=gpu:${TP}` flag (conflicted with `--exclusive`)

### ✅ Added (Simple)
- Use `generate_sweep_configs.py` (same as GitHub Actions)
- Call `runners/launch_b200-nv.sh` (reuse existing scripts)
- Let runner handle all container logic
- Removed `--gres` (runner uses `--exclusive` which allocates all GPUs)

## Configuration Example

```yaml
# In the script (lines 51-77), define your sweep:

dsr1-fp4-b200-sglang:
  image: lmsysorg/sglang:v0.5.3rc1-cu129-b200
  model: nvidia/DeepSeek-R1-0528-FP4-V2
  framework: sglang
  search-space:
    - { tp: 4, conc-start: 4, conc-end: 4 }      # Run conc=4
    - { tp: 4, conc-start: 32, conc-end: 32 }    # Run conc=32
    - { tp: 4, conc-start: 128, conc-end: 128 }  # Run conc=128

dsr1-fp4-b200-trt:
  # TRT-LLM with EP settings
  search-space:
    - { tp: 4, conc-start: 4, conc-end: 4 }          # EP=1 (default)
    - { tp: 4, conc-start: 32, conc-end: 32 }        # EP=1 (default)
    - { tp: 4, ep: 4, conc-start: 128, conc-end: 128 } # EP=4 for high conc
```

This generates **6 jobs total**: 3 SGLang + 3 TRT-LLM

## Quick Start

```bash
# 1. Set your token
export HF_TOKEN="hf_..."

# 2. Run the sweep
cd /path/to/InferenceMAX
bash manual-sweep-1k1k-scheduler.sh

# 3. Monitor (automatic, but you can check manually)
squeue -u $USER
tail -f /path/to/results/bmk_*.out

# 4. View results (after completion)
cd /lustre/.../results_1k1k_<timestamp>/
cat summary.txt
cat agg_dsr1_1k1k.json
```

## File Flow

```
Input:
  ├─ .github/configs/nvidia-master.yaml (reference for config format)
  ├─ runners/launch_b200-nv.sh (called for each job)
  ├─ benchmarks/dsr1_fp4_b200_*.sh (called by runner)
  └─ utils/*.py (processing and plotting)

Generated:
  ├─ temp_config.yaml (created from lines 51-77)
  ├─ sweep_configs.json (output from generate_sweep_configs.py)
  ├─ run_bmk_*.sh (wrapper scripts, one per job)
  └─ jobs.txt (tracking file)

Output:
  ├─ bmk_*_<job_id>.out/err (Slurm logs)
  ├─ agg_<result_filename>.json (processed results, one per job)
  ├─ agg_dsr1_1k1k.json (aggregated all results)
  ├─ summary.txt (human-readable summary)
  └─ tput_vs_*.png (Pareto plots)
```

## Why This Approach?

### Matches GitHub Actions Exactly
```python
# GitHub Actions workflow:
1. get-dsr1-configs: run generate_sweep_configs.py → JSON
2. benchmark-dsr1: for config in matrix → launch_b200-nv.sh
3. collect-results: collect_results.py + plot_perf.py

# Manual script:
1. run generate_sweep_configs.py → JSON ✓
2. for config in JSON → launch_b200-nv.sh ✓
3. collect_results.py + plot_perf.py ✓
```

### Reuses Existing Infrastructure
- No need to rewrite container logic
- No need to rewrite benchmark scripts  
- No need to rewrite result processing
- Same behavior as CI/CD pipeline

### Easy to Maintain
- Change concurrency? Edit YAML (lines 51-77)
- Change TP? Edit YAML
- Add framework? Add YAML section
- Script logic stays the same!

## Result Structure

After running, you get organized results:

```bash
$ ls -lh results_1k1k_20250110_150000/

-rw-r--r-- sweep_configs.json              # 6 configs
-rw-r--r-- jobs.txt                        # 6 job IDs
-rw-r--r-- agg_dsr1_*_sglang_*_conc4.json  # Result 1
-rw-r--r-- agg_dsr1_*_sglang_*_conc32.json # Result 2
-rw-r--r-- agg_dsr1_*_sglang_*_conc128.json # Result 3
-rw-r--r-- agg_dsr1_*_trt_*_conc4.json     # Result 4
-rw-r--r-- agg_dsr1_*_trt_*_conc32.json    # Result 5
-rw-r--r-- agg_dsr1_*_trt_*_conc128.json   # Result 6
-rw-r--r-- agg_dsr1_1k1k.json              # All aggregated
-rw-r--r-- summary.txt                     # Human-readable
-rw-r--r-- tput_vs_intvty_dsr1_1k1k.png    # Plot 1
-rw-r--r-- tput_vs_e2el_dsr1_1k1k.png      # Plot 2
```

Each result file contains:
```json
{
  "hw": "b200",
  "tp": 4,
  "ep": 1,
  "conc": 32,
  "framework": "sglang",
  "precision": "fp4",
  "tput_per_gpu": 1234.5,
  "median_e2el": 2.34,
  "median_intvty": 45.6,
  ...
}
```

## Customization Examples

### Test More Concurrency Values
```yaml
# Add lines in the search-space:
- { tp: 4, conc-start: 8, conc-end: 8 }
- { tp: 4, conc-start: 16, conc-end: 16 }
- { tp: 4, conc-start: 64, conc-end: 64 }
- { tp: 4, conc-start: 256, conc-end: 256 }
```

### Test TP=8 (8 GPUs)
```yaml
search-space:
  - { tp: 8, conc-start: 4, conc-end: 128 }
```

### Test Only SGLang
```bash
# Comment out or remove the dsr1-fp4-b200-trt section
```

### Test Different Model
```yaml
# Change model path and update image
model: deepseek-ai/DeepSeek-R1-0528  # FP8 version
image: lmsysorg/sglang:v0.5.2rc2-cu126
```

## Advantages

| Feature | Old Script | New Script |
|---------|-----------|------------|
| Lines of code | ~450 | ~310 |
| Config generation | Bash arrays | Python script ✓ |
| Runner scripts | Inline | Reused ✓ |
| Benchmark scripts | Inline | Reused ✓ |
| Maintainability | Complex | Simple ✓ |
| Matches GitHub Actions | Partially | Exactly ✓ |
| `--gres` flag | Included | Removed ✓ |

## Next Steps

1. **Run the script**: Test with default configs
2. **Customize**: Edit YAML section for your needs
3. **Scale up**: Add more frameworks, models, hardware
4. **Automate**: Schedule with cron or integrate into CI/CD

---

**Bottom Line**: The simplified script does the same thing as GitHub Actions, but runs on Slurm manually. It reuses all existing infrastructure and is much easier to understand and maintain!

