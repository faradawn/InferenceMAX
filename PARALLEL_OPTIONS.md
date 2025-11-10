# Parallel Execution Options

## Current Situation

The sequential script (`run-sweep-from-json.sh`) uses `salloc` which:
- Allocates a node and **waits**
- Runs the benchmark
- **Blocks** until complete before moving to next config

For 14 configs, this means they run one after another (could take many hours).

## Option 1: ✅ Parallel Submission (Recommended)

**Script**: `run-sweep-parallel.sh`

### How it works:
```bash
# Submit ALL jobs to Slurm queue at once
for config in configs:
    sbatch job_script.sh  # Returns immediately

# Monitor all jobs
while jobs_running:
    check_status()
    sleep 30

# Aggregate when all done
```

### Advantages:
- ✅ **All jobs run in parallel** (Slurm schedules them)
- ✅ **No waiting** - submit all at once
- ✅ **Slurm manages resources** - optimal scheduling
- ✅ **Can check status** with `squeue -u $USER`
- ✅ **Jobs survive logout** - runs in Slurm queue

### Usage:
```bash
export HF_TOKEN="your_token"
bash run-sweep-parallel.sh envs/dsr1_1k1k_fp4_trtllm.json
```

Output:
```
Submitting 14 jobs to Slurm...

[1/14] Submitted: bmk_trt_tp4_ep1_conc4 (Job ID: 1234567)
[2/14] Submitted: bmk_trt_tp4_ep1_conc8 (Job ID: 1234568)
...
[14/14] Submitted: bmk_trt_tp8_ep8_conc256 (Job ID: 1234580)

All 14 jobs submitted!

Monitor with: squeue -u $USER

Waiting for jobs to complete...
[10:30:15] Running: 14/14, Completed: 0/14
[10:30:45] Running: 12/14, Completed: 2/14
...
```

### Monitoring:
```bash
# Watch job status
watch -n 10 squeue -u $USER

# Check specific job output
tail -f results_<timestamp>/bmk_*_<job_id>.out
```

## Option 2: Slurm Job Arrays

Create a single job array that runs all configs:

```bash
#!/bin/bash
#SBATCH --array=0-13  # 14 configs (0-13)
#SBATCH --account=coreai_prod_infbench
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --exclusive

# Read config at index $SLURM_ARRAY_TASK_ID
CONFIG=$(jq ".[$SLURM_ARRAY_TASK_ID]" configs.json)
# ... run benchmark ...
```

### Advantages:
- ✅ Single job submission
- ✅ Slurm manages array scheduling
- ✅ Easy to cancel entire array: `scancel <job_id>`

### Disadvantages:
- ❌ More complex setup
- ❌ Harder to debug individual tasks

## Option 3: Background Jobs (Not Recommended)

```bash
for config in configs:
    salloc ... &  # Run in background
done
wait
```

### Disadvantages:
- ❌ Requires shell to stay open
- ❌ Hard to manage/monitor
- ❌ Messy if shell disconnects
- ❌ Resource contention issues

## Comparison Table

| Feature | Sequential | Parallel (sbatch) | Job Arrays |
|---------|-----------|-------------------|------------|
| Speed | ❌ Slow (one at a time) | ✅ Fast (all parallel) | ✅ Fast |
| Setup | ✅ Simple | ✅ Simple | ⚠️ Complex |
| Monitoring | ✅ Easy | ✅ Easy | ⚠️ Harder |
| Debugging | ✅ Easy (see immediately) | ✅ Easy (check logs) | ⚠️ Harder |
| Resource usage | ✅ Minimal | ⚠️ Needs queue slots | ⚠️ Needs queue slots |
| Can logout | ❌ No (blocks shell) | ✅ Yes | ✅ Yes |

## Recommended Approach

### For Testing (1-3 configs):
```bash
# Use sequential - easier to debug
bash run-sweep-from-json.sh test_configs.json
```

### For Production (10+ configs):
```bash
# Use parallel - much faster
bash run-sweep-parallel.sh envs/dsr1_1k1k_fp4_trtllm.json
```

## Resource Considerations

With 14 jobs running in parallel:
- Each job needs: 1 node, 4-8 GPUs (depending on TP), 3 hours
- Check your allocation: `sacctmgr show association user=$USER`
- Slurm will queue jobs if not enough resources available

## Monitoring Parallel Jobs

```bash
# View all your jobs
squeue -u $USER

# View specific job details
scontrol show job <job_id>

# View job output in real-time
tail -f results_<timestamp>/bmk_*_<job_id>.out

# Cancel all jobs
scancel -u $USER

# Cancel specific job
scancel <job_id>
```

## Results Collection

Both scripts collect results automatically when all jobs complete:
```
results_<timestamp>/
├── job_bmk_trt_tp4_ep1_conc4.sh              # Job script
├── bmk_trt_tp4_ep1_conc4_1234567.out         # Job stdout
├── bmk_trt_tp4_ep1_conc4_1234567.err         # Job stderr
├── agg_dsr1_1k1k_fp4_trt_tp4_ep1_..._b200.json  # Result
├── agg_dsr1_1k1k.json                        # Aggregated
├── tput_vs_intvty_dsr1_1k1k.png              # Plot
└── tput_vs_e2el_dsr1_1k1k.png                # Plot
```

## Troubleshooting

### Jobs not starting?
```bash
# Check queue status
squeue -u $USER

# Check why job is pending
scontrol show job <job_id> | grep Reason
```

Common reasons:
- `Resources`: Not enough GPUs/nodes available
- `Priority`: Other jobs have higher priority
- `QOSMaxJobsPerUser`: Hit job limit

### Job failed?
```bash
# Check error log
cat results_<timestamp>/bmk_*_<job_id>.err

# Check job exit code
sacct -j <job_id> --format=JobID,State,ExitCode
```

## Summary

For your use case (14 configs):

**Best choice**: `run-sweep-parallel.sh`
- Submit all 14 jobs at once
- Slurm schedules them optimally
- Complete in ~3 hours (vs ~42 hours sequential if each takes 3h)
- Easy to monitor and debug

