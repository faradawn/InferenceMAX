# Results Structure

## Results Directory

Both scripts now save results to:
```
/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/parallel_results/run_<timestamp>/
```

## Files Saved Per Benchmark

For each config run, you get:

### 1. Raw Benchmark Result (from bench_serving)
```
dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json
```

**Contains**: Raw output from the benchmark_serving.py script
- Request/response data
- Latency percentiles (ttft, tpot, itl, e2el)
- Throughput metrics
- All timing information

**Example**:
```json
{
  "model_id": "nvidia/DeepSeek-R1-0528-FP4-V2",
  "backend": "openai",
  "total_token_throughput": 12345.67,
  "output_throughput": 8901.23,
  "ttft_ms_mean": 123.45,
  "ttft_ms_median": 120.00,
  "tpot_ms_mean": 12.34,
  "e2el_ms_median": 5678.90,
  "max_concurrency": 4,
  "num_prompts": 40,
  ...
}
```

### 2. Processed Result (from process_result.py)
```
agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json
```

**Contains**: Raw data + metadata (hw, tp, framework, etc.)
- All raw benchmark data
- **Plus** hardware/config metadata
- **Plus** derived metrics (tput_per_gpu, intvty)

**Example**:
```json
{
  "hw": "b200",
  "tp": 4,
  "ep": 1,
  "dp_attention": "false",
  "conc": 4,
  "model": "nvidia/DeepSeek-R1-0528-FP4-V2",
  "framework": "trt",
  "precision": "fp4",
  "tput_per_gpu": 3086.42,
  "output_tput_per_gpu": 2225.31,
  "median_e2el": 5.67890,
  "median_intvty": 81.02,
  "median_ttft": 0.12000,
  ...
}
```

### 3. Job Logs (parallel only)
```
bmk_trt_tp4_ep1_conc4_<job_id>.out    # stdout
bmk_trt_tp4_ep1_conc4_<job_id>.err    # stderr
job_bmk_trt_tp4_ep1_conc4.sh          # job script
```

## Aggregated Results

After all configs complete:

### 4. Aggregated JSON
```
agg_dsr1_1k1k.json
```

**Contains**: Array of all processed results
```json
[
  {
    "hw": "b200",
    "tp": 4,
    "conc": 4,
    "tput_per_gpu": 3086.42,
    ...
  },
  {
    "hw": "b200",
    "tp": 4,
    "conc": 8,
    "tput_per_gpu": 4123.56,
    ...
  },
  ...
]
```

### 5. Performance Plots
```
tput_vs_intvty_dsr1_1k1k.png    # Throughput vs Interactivity
tput_vs_e2el_dsr1_1k1k.png      # Throughput vs Latency
```

**Pareto frontier plots** showing optimal configurations

## Complete Directory Structure

```
/lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/parallel_results/
├── run_20251110_100000/
│   ├── jobs.txt                                           # Job tracking
│   │
│   ├── job_bmk_trt_tp4_ep1_conc4.sh                       # Job script
│   ├── bmk_trt_tp4_ep1_conc4_1234567.out                  # Job stdout
│   ├── bmk_trt_tp4_ep1_conc4_1234567.err                  # Job stderr
│   │
│   ├── dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json           # Raw result
│   ├── agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json       # Processed result
│   │
│   ├── dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc8_b200.json           # Raw result
│   ├── agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc8_b200.json       # Processed result
│   │
│   ├── ... (more configs)
│   │
│   ├── agg_dsr1_1k1k.json                                 # All results aggregated
│   ├── tput_vs_intvty_dsr1_1k1k.png                       # Plot 1
│   └── tput_vs_e2el_dsr1_1k1k.png                         # Plot 2
│
└── run_20251110_143000/
    └── ... (another run)
```

## Usage

### View Raw Benchmark Data
```bash
cat parallel_results/run_<timestamp>/dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json
```

### View Processed Data (with metadata)
```bash
cat parallel_results/run_<timestamp>/agg_dsr1_1k1k_fp4_trt_tp4_ep1_dpa_false_conc4_b200.json
```

### View All Results Together
```bash
cat parallel_results/run_<timestamp>/agg_dsr1_1k1k.json | jq '.'
```

### Compare Specific Metrics
```bash
# Get throughput for all configs
jq '.[].tput_per_gpu' parallel_results/run_<timestamp>/agg_dsr1_1k1k.json

# Get best config by throughput
jq 'sort_by(.tput_per_gpu) | reverse | .[0]' parallel_results/run_<timestamp>/agg_dsr1_1k1k.json
```

### View Plots
```bash
# On cluster (with X forwarding)
display parallel_results/run_<timestamp>/tput_vs_intvty_dsr1_1k1k.png

# Or copy to local machine
scp cluster:/.../parallel_results/run_<timestamp>/*.png .
```

## File Purposes

| File | Purpose | Who Uses It |
|------|---------|-------------|
| Raw JSON | Benchmark raw output | Debugging, detailed analysis |
| Processed JSON (`agg_*`) | Results with metadata | Aggregation, plotting |
| Aggregated JSON | All configs together | Analysis, comparisons |
| Plots | Visualization | Reports, presentations |
| Job logs | Debugging | Troubleshooting failures |

## Cleanup

Old results can be archived or deleted:

```bash
# List all runs
ls -lh /lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/parallel_results/

# Delete old runs
rm -rf /lustre/fsw/coreai_prod_infbench/faradawny/InferenceMAX/parallel_results/run_20251110_100000/

# Archive important runs
tar -czf dsr1_1k1k_20251110.tar.gz parallel_results/run_20251110_100000/
```

