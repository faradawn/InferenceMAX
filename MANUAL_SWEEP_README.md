# Manual Sweep Execution Guide

This guide explains how to manually run InferenceMAX benchmark sweeps on a Slurm cluster, mimicking the automated GitHub Actions workflow.

## Overview

The manual sweep script (`manual-sweep-1k1k-scheduler.sh`) follows the exact same execution flow as the GitHub Actions workflow:

1. **Generate Configs** - Define sweep parameters (models, frameworks, TP, concurrency)
2. **Launch Benchmarks** - Submit Slurm jobs for each configuration
3. **Monitor Progress** - Wait for all jobs to complete
4. **Collect Results** - Aggregate individual benchmark results
5. **Generate Plots** - Create Pareto frontier visualizations

## Prerequisites

### Environment Setup

Make sure the following are configured:

```bash
# Required environment variables
export HF_TOKEN="your_huggingface_token"
export SLURM_ACCOUNT="coreai_prod_infbench"
export SLURM_PARTITION="batch"
```

### Cluster Resources

- Access to B200 nodes with 4+ GPUs
- Slurm account with sufficient allocation
- Access to shared HuggingFace cache at `/lustre/fsw/coreai_prod_infbench/common/cache/hub/`
- Write access to `/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/`

## Quick Start

### 1. Run the Full Sweep

```bash
cd /path/to/InferenceMAX
bash manual-sweep-1k1k-scheduler.sh
```

This will:
- Test **DeepSeek-R1 FP4** on **B200** hardware
- Run both **SGLang** and **TRT-LLM** frameworks
- Test sequence lengths: **1024 input / 1024 output** (1k1k)
- Use **TP=4** (single node, 4 GPUs)
- Sweep concurrency: **4, 32, 128**
- Total: **6 benchmark jobs** (3 concurrency × 2 frameworks)

### 2. Monitor Progress

The script automatically monitors job progress. You can also check manually:

```bash
# Check running jobs
squeue -u $USER

# View specific job output
tail -f /lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_1k1k_*/bmk_*_<job_id>.out

# Check all results
ls -lh /lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_1k1k_*/
```

### 3. View Results

After completion, results are saved in a timestamped directory:

```bash
cd /lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_1k1k_<timestamp>/

# View summary
cat summary.txt

# View individual results
cat agg_dsr1_1k1k_fp4_sglang_tp4_ep1_dpa_false_conc32_b200.json

# View aggregated results
cat agg_dsr1_1k1k.json

# View plots
display tput_vs_intvty_dsr1_1k1k.png
display tput_vs_e2el_dsr1_1k1k.png
```

## Configuration

### Modify Sweep Parameters

Edit `manual-sweep-1k1k-scheduler.sh` to customize:

```bash
# Line 30-32: Concurrency values
CONC_VALUES=(4 32 128)  # Change to: (4 8 16 32 64 128)

# Line 35: Frameworks
FRAMEWORKS=("sglang" "trt")  # Change to: ("sglang") for SGLang only

# Line 25: Tensor Parallelism
export TP=4  # Change to: 8 for 8 GPUs

# Line 18-21: Sequence lengths
export ISL=1024  # Change to: 8192 for 8k input
export OSL=1024  # Change to: 8192 for 8k output
```

### Test Different Models

To test gpt-oss-120b instead:

```bash
# Change line 17
export MODEL_PREFIX="gptoss"

# Update model names (lines 56-61)
SGLANG_MODEL="openai/gpt-oss-120b"
TRT_MODEL="openai/gpt-oss-120b"

# Update images
SGLANG_IMAGE="vllm/vllm-openai:v0.11.0"
TRT_IMAGE="nvcr.io#nvidia/tensorrt-llm/release:1.2.0rc0.post1"
```

## Workflow Architecture

### Job Submission Flow

```
manual-sweep-1k1k-scheduler.sh
    │
    ├─ Generate configs (frameworks × concurrency values)
    │
    ├─ For each config:
    │   ├─ Create launch script (launch_bmk_*.sh)
    │   ├─ Submit to Slurm via sbatch
    │   └─ Job runs:
    │       ├─ Import Docker image → squash file (enroot)
    │       ├─ Launch container via srun
    │       ├─ Run benchmark script:
    │       │   ├─ SGLang: benchmarks/dsr1_fp4_b200_docker.sh
    │       │   └─ TRT-LLM: benchmarks/dsr1_fp4_b200_trt_slurm.sh
    │       ├─ Process results (utils/process_result.py)
    │       └─ Save to results directory
    │
    ├─ Monitor all jobs until completion
    │
    ├─ Collect results (utils/collect_results.py)
    │
    └─ Generate plots (utils/plot_perf.py)
```

### Directory Structure

```
/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/
└── results_1k1k_20250110_143022/
    ├── launch_bmk_sglang_tp4_conc4.sh       # Job launch script
    ├── bmk_sglang_tp4_conc4_12345.out       # Job stdout
    ├── bmk_sglang_tp4_conc4_12345.err       # Job stderr
    ├── agg_dsr1_1k1k_fp4_sglang_*.json      # Processed result
    ├── agg_dsr1_1k1k.json                   # Aggregated results
    ├── summary.txt                           # Human-readable summary
    ├── tput_vs_intvty_dsr1_1k1k.png         # Throughput vs Interactivity plot
    └── tput_vs_e2el_dsr1_1k1k.png           # Throughput vs Latency plot
```

## Benchmark Scripts Used

The scheduler automatically selects the correct benchmark script:

| Framework | Script | Container Type |
|-----------|--------|----------------|
| SGLang    | `benchmarks/dsr1_fp4_b200_docker.sh` | Enroot + Docker |
| TRT-LLM   | `benchmarks/dsr1_fp4_b200_trt_slurm.sh` | Enroot + Docker |

Both run via Slurm's enroot containerization (not native Slurm scripts).

## Advanced Configuration

### EP (Expert Parallelism) and DP_ATTN Settings

For TRT-LLM with TP=4 at 1k1k, the script uses InferenceMAX's recommended settings:

| Concurrency | EP Size | DP Attention |
|-------------|---------|--------------|
| 4           | 1       | false        |
| 8           | 1       | false        |
| 16          | 1       | false        |
| 32          | 1       | false        |
| 64          | 4       | false        |
| 128         | 4       | false        |
| 256         | 4       | true         |

These are defined in lines 69-78 of the scheduler script and match `.github/configs/nvidia-master.yaml`.

### Customizing EP/DP_ATTN

To modify these settings:

```bash
# Edit lines 69-78 in manual-sweep-1k1k-scheduler.sh
EP_SETTINGS[128]=8        # Change EP from 4 to 8
DP_ATTN_SETTINGS[128]="true"  # Enable DP_ATTN for conc=128
```

## Troubleshooting

### Issue: "Job submission failed"

**Solution**: Check Slurm allocation and partition access:
```bash
sinfo -p batch
sacctmgr show association user=$USER
```

### Issue: "Squash file creation failed"

**Solution**: Ensure you have write access to the squash directory:
```bash
ls -ld /lustre/fsw/coreai_prod_infbench/common/squash/
# If needed, create manually:
enroot import -o /tmp/test.sqsh docker://lmsysorg/sglang:v0.5.3rc1-cu129-b200
```

### Issue: "Benchmark result not found"

**Solution**: Check the job error log:
```bash
cat /path/to/results/bmk_*_<job_id>.err
# Common issues: HF_TOKEN not set, model not cached, GPU OOM
```

### Issue: "No result files found"

**Solution**: Check if jobs actually completed:
```bash
# Check job status
sacct -u $USER --format=JobID,JobName,State,ExitCode

# View failed job logs
grep -i error /path/to/results/*.err
```

## Comparison to GitHub Actions

| Feature | GitHub Actions | Manual Script |
|---------|----------------|---------------|
| Trigger | Scheduled/Manual | Manual only |
| Config Generation | Python script | Bash arrays |
| Job Execution | Matrix strategy | Loop + sbatch |
| Parallelization | Automatic | Concurrent Slurm jobs |
| Monitoring | GitHub UI | Script polling |
| Results Storage | GitHub Artifacts | Lustre filesystem |

## Next Steps

1. **Run 1k8k and 8k1k sweeps**: Create `manual-sweep-1k8k-scheduler.sh` and `manual-sweep-8k1k-scheduler.sh`
2. **Test on other hardware**: Modify runner type to `h200`, `mi300x`, etc.
3. **Automate with cron**: Schedule periodic sweeps
4. **Compare results**: Use plotting utilities to compare across runs

## Contact

For questions or issues, refer to the main InferenceMAX documentation or GitHub Actions workflow files in `.github/workflows/`.

