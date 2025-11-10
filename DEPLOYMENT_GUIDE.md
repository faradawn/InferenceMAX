# Manual Sweep Scripts - Deployment Guide

## 📦 Files Created

I've created 3 files for manual benchmark execution on your Slurm cluster:

1. **`manual-sweep-1k1k-scheduler.sh`** - Main production sweep script
2. **`manual-sweep-1k1k-test.sh`** - Single-job test script to validate setup
3. **`MANUAL_SWEEP_README.md`** - Comprehensive documentation

## 🚀 Deployment Steps

### Step 1: Upload to Remote Cluster

From your local machine, upload these files to the cluster:

```bash
# Set your cluster details
CLUSTER_USER="your_username"
CLUSTER_HOST="your.cluster.hostname"
CLUSTER_PATH="/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX"

# Upload the scripts (from your local InferenceMAX directory)
scp manual-sweep-1k1k-scheduler.sh ${CLUSTER_USER}@${CLUSTER_HOST}:/path/to/InferenceMAX/
scp manual-sweep-1k1k-test.sh ${CLUSTER_USER}@${CLUSTER_HOST}:/path/to/InferenceMAX/
scp MANUAL_SWEEP_README.md ${CLUSTER_USER}@${CLUSTER_HOST}:/path/to/InferenceMAX/

# Or upload the entire repository if using git
# The scripts are already in your InferenceMAX repo
```

### Step 2: SSH to Cluster and Setup

```bash
ssh ${CLUSTER_USER}@${CLUSTER_HOST}

# Navigate to your InferenceMAX directory
cd /path/to/InferenceMAX

# Make scripts executable
chmod +x manual-sweep-1k1k-scheduler.sh
chmod +x manual-sweep-1k1k-test.sh

# Set your HuggingFace token
export HF_TOKEN="your_huggingface_token_here"

# Verify environment
echo "Checking prerequisites..."
which sbatch srun enroot python3
```

### Step 3: Run Test (Recommended First)

```bash
# Run a single benchmark test to validate setup
bash manual-sweep-1k1k-test.sh

# This will:
# - Submit 1 SGLang job with TP=4, CONC=4
# - Create squash file (first time only, ~5-10 min)
# - Run benchmark (~10-15 min)
# - Monitor and report results
```

### Step 4: Run Full Sweep

Once the test passes:

```bash
# Run the full sweep
bash manual-sweep-1k1k-scheduler.sh

# This will:
# - Submit 6 jobs (SGLang + TRT-LLM × 3 concurrency values)
# - Monitor all jobs until completion
# - Aggregate results and generate plots
```

## 📋 What the Scripts Do

### Architecture Overview

```
manual-sweep-1k1k-scheduler.sh
│
├─ Configuration
│  ├─ DeepSeek-R1 FP4 model
│  ├─ B200 hardware (TP=4, single node)
│  ├─ Sequence lengths: 1024 input / 1024 output
│  ├─ Frameworks: SGLang, TRT-LLM
│  └─ Concurrency: 4, 32, 128
│
├─ Step 1: Generate Configs (6 total)
│  ├─ SGLang: CONC=4, 32, 128
│  └─ TRT-LLM: CONC=4 (EP=1), 32 (EP=1), 128 (EP=4)
│
├─ Step 2: Launch Jobs via Slurm
│  ├─ For each config:
│  │   ├─ Create launch script
│  │   ├─ Submit via sbatch
│  │   └─ Job workflow:
│  │       ├─ Import Docker image → enroot squash
│  │       ├─ Launch container via srun
│  │       ├─ Run benchmark script:
│  │       │   ├─ SGLang: benchmarks/dsr1_fp4_b200_docker.sh
│  │       │   └─ TRT-LLM: benchmarks/dsr1_fp4_b200_trt_slurm.sh
│  │       ├─ Process result (utils/process_result.py)
│  │       └─ Save to results directory
│  │
│  └─ Jobs run in parallel
│
├─ Step 3: Monitor Progress
│  └─ Poll job status every 30s until all complete
│
├─ Step 4: Collect Results
│  ├─ Run summarize.py (human-readable summary)
│  └─ Run collect_results.py (aggregate JSON)
│
└─ Step 5: Generate Plots
    ├─ Throughput vs Interactivity
    └─ Throughput vs End-to-End Latency
```

### Benchmark Execution Flow

Each job follows the GitHub Actions workflow exactly:

```bash
# 1. Resource Cleanup (handled by Slurm job isolation)

# 2. Launch Container with Enroot
enroot import -o /path/to/image.sqsh docker://IMAGE_NAME
srun --container-image=image.sqsh \
     --container-mounts=workspace:/workspace,cache:/cache \
     bash benchmarks/BENCHMARK_SCRIPT.sh

# 3. Benchmark Script runs:
#    - Launches inference server (SGLang or TRT-LLM)
#    - Waits for server ready
#    - Runs bench_serving benchmark
#    - Saves result JSON

# 4. Process Result
python3 utils/process_result.py
# Creates agg_RESULT_FILENAME.json with metrics

# 5. Copy to results directory
```

## 📊 Expected Results

After completion, you'll find:

```
/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_1k1k_TIMESTAMP/
│
├─ Launch Scripts (one per job)
│  ├─ launch_bmk_sglang_tp4_conc4.sh
│  ├─ launch_bmk_sglang_tp4_conc32.sh
│  └─ ... (6 total)
│
├─ Job Logs
│  ├─ bmk_sglang_tp4_conc4_12345.out
│  ├─ bmk_sglang_tp4_conc4_12345.err
│  └─ ... (6 pairs)
│
├─ Individual Results (one per job)
│  ├─ agg_dsr1_1k1k_fp4_sglang_tp4_ep1_dpa_false_conc4_b200.json
│  ├─ agg_dsr1_1k1k_fp4_sglang_tp4_ep1_dpa_false_conc32_b200.json
│  ├─ agg_dsr1_1k1k_fp4_sglang_tp4_ep1_dpa_false_conc128_b200.json
│  ├─ agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json
│  ├─ agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc32_b200.json
│  └─ agg_dsr1_1k1k_fp4_trt_tp4_ep4_dpa_false_conc128_b200.json
│
├─ Aggregated Results
│  ├─ agg_dsr1_1k1k.json          # All results combined
│  └─ summary.txt                  # Human-readable summary
│
└─ Performance Plots
   ├─ tput_vs_intvty_dsr1_1k1k.png
   ├─ tput_vs_e2el_dsr1_1k1k.png
   ├─ tput_vs_intvty_dsr1_dsr1_1k1k.png
   └─ tput_vs_e2el_dsr1_dsr1_1k1k.png
```

### Result JSON Schema

Each `agg_*.json` file contains:

```json
{
  "hw": "b200",
  "tp": 4,
  "ep": 1,
  "dp_attention": "false",
  "conc": 32,
  "model": "nvidia/DeepSeek-R1-0528-FP4-V2",
  "framework": "sglang",
  "precision": "fp4",
  "tput_per_gpu": 1234.56,
  "output_tput_per_gpu": 890.12,
  "input_tput_per_gpu": 344.44,
  "median_e2el": 1.234,
  "median_intvty": 78.9,
  "median_ttft": 0.456,
  "median_tpot": 0.012
}
```

## ⚙️ Customization

### Change Concurrency Range

Edit `manual-sweep-1k1k-scheduler.sh`, line 30:

```bash
# Current: 3 values
CONC_VALUES=(4 32 128)

# Full range: 6 values
CONC_VALUES=(4 8 16 32 64 128)
```

### Test Only One Framework

Edit line 35:

```bash
# Only SGLang
FRAMEWORKS=("sglang")

# Only TRT-LLM
FRAMEWORKS=("trt")
```

### Use 8 GPUs (TP=8)

Edit line 25:

```bash
export TP=8
```

**Important**: Also update EP/DP_ATTN settings (lines 69-78) to match TP=8 configs from `.github/configs/nvidia-master.yaml`.

### Test Different Sequence Lengths

For 1k8k or 8k1k, copy the scheduler and modify:

```bash
# For 1k8k
export ISL=1024
export OSL=8192
export MAX_MODEL_LEN=10240
export EXP_NAME="dsr1_1k8k"

# For 8k1k
export ISL=8192
export OSL=1024
export MAX_MODEL_LEN=10240
export EXP_NAME="dsr1_8k1k"
```

## 🔍 Monitoring Jobs

### Check Job Queue

```bash
# All your jobs
squeue -u $USER

# Specific job details
squeue -j JOB_ID

# Job accounting info
sacct -j JOB_ID --format=JobID,JobName,State,Elapsed,AllocCPUS,AllocGPU
```

### View Live Logs

```bash
# Tail job output
tail -f /lustre/.../results_1k1k_*/bmk_*_JOBID.out

# View errors
tail -f /lustre/.../results_1k1k_*/bmk_*_JOBID.err

# Check all running jobs
watch -n 10 squeue -u $USER
```

### Cancel Jobs

```bash
# Cancel specific job
scancel JOB_ID

# Cancel all your jobs
scancel -u $USER

# Cancel jobs matching pattern
scancel -n bmk_sglang
```

## 🐛 Troubleshooting

### Issue: "sbatch: error: Batch job submission failed"

**Cause**: Invalid Slurm account or partition

**Solution**:
```bash
# Check available partitions
sinfo

# Check your account
sacctmgr show association user=$USER

# Update script if needed (lines 14-15)
export SLURM_ACCOUNT="your_actual_account"
export SLURM_PARTITION="your_partition"
```

### Issue: "enroot: command not found"

**Cause**: Enroot not available in PATH

**Solution**:
```bash
# Load enroot module if available
module load enroot

# Or check with sysadmin for enroot installation
which enroot
```

### Issue: "Squash file creation failed"

**Cause**: No write access or disk quota exceeded

**Solution**:
```bash
# Check disk space
df -h /lustre/fsw/coreai_prod_infbench/common/squash/

# Check your quota
quota -s

# Alternative: Use local temp directory
export SQUASH_FILE="/tmp/$(echo "$IMAGE" | sed 's/[\/:@#]/_/g').sqsh"
```

### Issue: "Benchmark result not found"

**Common causes**:
1. **HF_TOKEN not set** → Export before running script
2. **Model not cached** → First run downloads model (~10 min)
3. **GPU OOM** → Try lower concurrency or higher TP
4. **Server startup failure** → Check .err log for errors

**Debug**:
```bash
# Check error log
cat /path/to/results/bmk_*_JOBID.err

# Check if server started
grep -i "fired up and ready" /path/to/results/bmk_*_JOBID.out

# Check GPU memory
grep -i "out of memory" /path/to/results/bmk_*_JOBID.err
```

### Issue: "Jobs stuck in pending state"

**Cause**: Not enough available resources

**Solution**:
```bash
# Check why job is pending
squeue -j JOB_ID -o "%.18i %.9P %.30j %.8u %.8T %.10M %.9l %.6D %.20R"

# Check partition availability
sinfo -p batch

# May need to wait for resources to free up
```

## 📈 Analyzing Results

### Quick Summary

```bash
cd /lustre/.../results_1k1k_TIMESTAMP/

# View summary
cat summary.txt

# Pretty-print aggregated results
python3 -m json.tool agg_dsr1_1k1k.json | less
```

### Extract Key Metrics

```bash
# Compare throughput across configs
jq '.[] | {framework, conc, tput: .tput_per_gpu}' agg_dsr1_1k1k.json

# Find best throughput
jq 'max_by(.tput_per_gpu) | {framework, tp, conc, tput: .tput_per_gpu}' agg_dsr1_1k1k.json

# Find best latency
jq 'min_by(.median_e2el) | {framework, tp, conc, latency: .median_e2el}' agg_dsr1_1k1k.json
```

### View Plots

```bash
# Copy plots to local machine for viewing
scp user@cluster:/lustre/.../results_1k1k_*/tput_vs_*.png .

# Or view on cluster if X11 forwarding enabled
display tput_vs_intvty_dsr1_1k1k.png
```

## 🔄 Next Steps

### Create 1k8k and 8k1k Sweeps

```bash
# Copy and modify for 1k8k
cp manual-sweep-1k1k-scheduler.sh manual-sweep-1k8k-scheduler.sh
# Edit ISL=1024, OSL=8192, EXP_NAME="dsr1_1k8k"

# Copy and modify for 8k1k
cp manual-sweep-1k1k-scheduler.sh manual-sweep-8k1k-scheduler.sh
# Edit ISL=8192, OSL=1024, EXP_NAME="dsr1_8k1k"
```

### Automate with Cron

```bash
# Edit crontab
crontab -e

# Run daily at 2 AM
0 2 * * * cd /path/to/InferenceMAX && bash manual-sweep-1k1k-scheduler.sh >> /path/to/sweep.log 2>&1
```

### Compare Multiple Runs

```bash
# Compare two different runs
python3 utils/plot_perf.py results_1k1k_RUN1/ dsr1_1k1k
python3 utils/plot_perf.py results_1k1k_RUN2/ dsr1_1k1k

# Merge results for comparison
cat results_1k1k_RUN1/agg_dsr1_1k1k.json results_1k1k_RUN2/agg_dsr1_1k1k.json | \
jq -s 'add' > combined_results.json
```

## 📞 Support

If you encounter issues:

1. Check `MANUAL_SWEEP_README.md` for detailed documentation
2. Review job logs in the results directory
3. Compare with GitHub Actions workflow in `.github/workflows/`
4. Verify your setup matches `runners/launch_b200-nv.sh`

## ✅ Summary

**Files to upload:**
- `manual-sweep-1k1k-scheduler.sh` (main script)
- `manual-sweep-1k1k-test.sh` (test script)
- `MANUAL_SWEEP_README.md` (documentation)

**First-time setup:**
1. Upload files to cluster
2. `chmod +x *.sh`
3. `export HF_TOKEN="..."`
4. Run test: `bash manual-sweep-1k1k-test.sh`
5. Run full sweep: `bash manual-sweep-1k1k-scheduler.sh`

**Expected duration:**
- Test: ~20 minutes
- Full sweep: ~1-2 hours (6 jobs in parallel)

**Results location:**
`/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/results_1k1k_TIMESTAMP/`

Good luck with your benchmarks! 🚀

