# Manual Sweep Guide - Simplified

This guide explains the simplified manual sweep script that closely mimics the GitHub Actions workflow.

## Script Architecture

The script follows the **exact same 5-step workflow** as GitHub Actions:

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Generate Sweep Configs                              │
│   → Uses generate_sweep_configs.py (same as GitHub Actions) │
│   → Outputs JSON array of configurations                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Launch Benchmarks                                   │
│   → Loop through JSON array                                 │
│   → For each config: Call runners/launch_b200-nv.sh         │
│   → Runner script handles container + benchmark execution   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 3: Monitor Jobs                                        │
│   → Poll squeue until all jobs complete                     │
│   → Track completed/failed jobs                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 4: Collect Results                                     │
│   → Run utils/summarize.py                                  │
│   → Run utils/collect_results.py                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 5: Generate Plots                                      │
│   → Run utils/plot_perf.py                                  │
│   → Create Pareto frontier visualizations                   │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

### Step 1: Generate Configs (Lines 45-74)

Creates a temporary YAML config file with your sweep parameters:

```yaml
dsr1-fp4-b200-sglang:
  image: lmsysorg/sglang:v0.5.3rc1-cu129-b200
  model: nvidia/DeepSeek-R1-0528-FP4-V2
  framework: sglang
  search-space:
    - { tp: 4, conc-start: 4, conc-end: 4 }
    - { tp: 4, conc-start: 32, conc-end: 32 }
    - { tp: 4, conc-start: 128, conc-end: 128 }

dsr1-fp4-b200-trt:
  # Similar for TRT-LLM
```

Then calls: `python3 utils/matrix-logic/generate_sweep_configs.py full-sweep`

This outputs a JSON array like:
```json
[
  {
    "image": "lmsysorg/sglang:v0.5.3rc1-cu129-b200",
    "model": "nvidia/DeepSeek-R1-0528-FP4-V2",
    "framework": "sglang",
    "tp": 4,
    "ep": 1,
    "dp-attn": false,
    "conc": 4,
    ...
  },
  {
    "framework": "sglang",
    "tp": 4,
    "conc": 32,
    ...
  },
  ...
]
```

### Step 2: Launch Benchmarks (Lines 76-217)

**Key insight**: Instead of recreating logic, we **reuse existing scripts**!

For each config in the JSON:
1. **Parse the JSON** → Extract variables (IMAGE, MODEL, TP, CONC, etc.)
2. **Create wrapper script** → Sets environment variables
3. **Call `runners/launch_b200-nv.sh`** → This is the **same script GitHub Actions uses**!
4. **Submit to Slurm** via `sbatch`

The wrapper script (lines 118-167) is minimal:
```bash
# Export all environment variables
export IMAGE="..."
export MODEL="..."
export TP="4"
export CONC="32"
...

# Call the runner script (same as GitHub Actions!)
bash ./runners/launch_b200-nv.sh

# Process and save results
python3 utils/process_result.py
cp "agg_${RESULT_FILENAME}.json" "${RESULTS_DIR}/"
```

### Step 3: Monitor Jobs (Lines 219-262)

Simple polling loop:
```bash
while true; do
    # Check each job in jobs.txt
    if is_job_running "$JOB_ID"; then
        RUNNING_COUNT++
    elif result_file_exists; then
        COMPLETED_COUNT++
    else
        FAILED_COUNT++
    fi
    
    # Exit when all done
    if [ "$RUNNING_COUNT" -eq 0 ]; then
        break
    fi
    
    sleep 30
done
```

### Step 4: Collect Results (Lines 264-293)

Exactly like GitHub Actions:
```bash
python3 utils/summarize.py "${RESULTS_DIR}/"
python3 utils/collect_results.py "${RESULTS_DIR}/" "dsr1_1k1k"
```

### Step 5: Generate Plots (Lines 295-310)

Exactly like GitHub Actions:
```bash
python3 utils/plot_perf.py "${RESULTS_DIR}/" "dsr1_1k1k"
```

## Key Simplifications

### ✅ What's Different from Complex Version

| Old Approach | New Approach |
|--------------|--------------|
| Bash arrays for configs | Python script generates JSON |
| Inline Slurm job scripts | Call existing runner scripts |
| Custom container logic | Reuse `launch_b200-nv.sh` |
| Manual EP/DP_ATTN logic | Config file handles it |
| Removed `--gres=gpu:${TP}` | Runner script uses `--exclusive` |

### ✅ What's Reused from GitHub Actions

- `utils/matrix-logic/generate_sweep_configs.py` ← Config generation
- `runners/launch_b200-nv.sh` ← Job launcher
- `benchmarks/dsr1_fp4_b200_docker.sh` ← SGLang benchmark
- `benchmarks/dsr1_fp4_b200_trt_slurm.sh` ← TRT-LLM benchmark
- `utils/process_result.py` ← Result processing
- `utils/collect_results.py` ← Result aggregation
- `utils/plot_perf.py` ← Plotting

**Result**: Script is now ~300 lines instead of ~450, and **much simpler to understand!**

## Usage

### Quick Start

```bash
# Set your HuggingFace token
export HF_TOKEN="your_token_here"

# Run the sweep
cd /path/to/InferenceMAX
bash manual-sweep-1k1k-scheduler.sh
```

### Customize Configs

Edit lines 51-77 in the script to change:

```yaml
# Change concurrency values
- { tp: 4, conc-start: 4, conc-end: 4 }      # Test conc=4
- { tp: 4, conc-start: 32, conc-end: 32 }    # Test conc=32
- { tp: 4, conc-start: 128, conc-end: 128 }  # Test conc=128

# Add more values:
- { tp: 4, conc-start: 8, conc-end: 8 }      # Test conc=8
- { tp: 4, conc-start: 64, conc-end: 64 }    # Test conc=64

# Change TP:
- { tp: 8, conc-start: 4, conc-end: 128 }    # Test TP=8

# For TRT-LLM, add EP and DP_ATTN:
- { tp: 4, ep: 4, dp-attn: true, conc-start: 256, conc-end: 256 }
```

### Test Different Frameworks

To test only SGLang:
```bash
# Comment out the TRT-LLM section in the config (lines 65-77)
```

To test only TRT-LLM:
```bash
# Comment out the SGLang section in the config (lines 51-64)
```

## Directory Structure

After running, you'll get:

```
/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_1k1k_20250110_150000/
├── sweep_configs.json                        # Generated JSON array
├── temp_config.yaml                          # Temp config file
├── jobs.txt                                  # Job tracking file
├── run_bmk_sglang_tp4_ep1_conc4.sh          # Wrapper script
├── bmk_sglang_tp4_ep1_conc4_12345.out       # Job stdout
├── bmk_sglang_tp4_ep1_conc4_12345.err       # Job stderr
├── agg_dsr1_1k1k_fp4_sglang_*.json          # Individual results
├── agg_dsr1_1k1k.json                       # Aggregated results
├── summary.txt                               # Text summary
├── tput_vs_intvty_dsr1_1k1k.png             # Plot 1
└── tput_vs_e2el_dsr1_1k1k.png               # Plot 2
```

## Troubleshooting

### Check Job Status

```bash
# View all your jobs
squeue -u $USER

# View specific job output
tail -f /path/to/results/bmk_*_<job_id>.out

# Check job accounting
sacct -u $USER --format=JobID,JobName,State,ExitCode
```

### Debug Failed Jobs

```bash
# Check error log
cat /path/to/results/bmk_*_<job_id>.err

# Check if result was created
ls -lh /path/to/results/agg_*.json

# Re-run a specific config manually
export IMAGE="..."
export MODEL="..."
export TP=4
export CONC=32
# ... set other vars ...
bash runners/launch_b200-nv.sh
```

## Comparison to GitHub Actions

The script is now **nearly identical** to the GitHub Actions workflow:

| GitHub Actions Step | Manual Script Line |
|---------------------|-------------------|
| `get-dsr1-configs` job | Lines 45-74 |
| `benchmark-dsr1` job matrix | Lines 76-217 |
| `workflow_dispatch` trigger | Manual execution |
| `collect-dsr1-results` job | Lines 264-293 |
| Plot generation | Lines 295-310 |

The main difference is **concurrency**:
- GitHub Actions: Runs all jobs in parallel
- Manual script: Submits all jobs to Slurm, which schedules them

## Next Steps

1. **Create 1k8k and 8k1k versions**: Copy and modify ISL/OSL values
2. **Test other hardware**: Change runner from `b200` to `h200`, `mi300x`, etc.
3. **Use full InferenceMAX configs**: Replace temp config with actual config files
4. **Automate**: Schedule with cron or run on-demand

## Summary

The simplified script:
- ✅ Uses the **same Python config generator** as GitHub Actions
- ✅ Calls the **same runner scripts** as GitHub Actions  
- ✅ Calls the **same benchmark scripts** as GitHub Actions
- ✅ Uses the **same result processing** as GitHub Actions
- ✅ Generates the **same plots** as GitHub Actions
- ✅ Removed the `--gres` line (uses `--exclusive` from runner script)
- ✅ **~150 lines shorter** and much easier to maintain!

