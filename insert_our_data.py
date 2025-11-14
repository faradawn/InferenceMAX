#!/usr/bin/env python3
"""
Script to merge TRT-LLM benchmark data into official benchmark data.
Matches records by hw, tp, and conc keys and replaces tput_per_gpu and median_intvty.
"""

import json
import sys
from pathlib import Path

def load_json(filepath):
    """Load JSON data from file."""
    with open(filepath, 'r') as f:
        return json.load(f)

def save_json(filepath, data):
    """Save JSON data to file with pretty formatting."""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)

def insert_our_data(official_file, our_file, output_file=None):
    """
    Merge our TRT-LLM data into official data.
    
    Args:
        official_file: Path to official benchmark data
        our_file: Path to our TRT-LLM benchmark data
        output_file: Optional output path (defaults to overwriting official_file)
    
    Returns:
        Number of records replaced
    """
    # Load both datasets
    print(f"Loading official data from: {official_file}")
    official_data = load_json(official_file)
    print(f"  Loaded {len(official_data)} records")
    
    print(f"\nLoading our TRT-LLM data from: {our_file}")
    our_data = load_json(our_file)
    print(f"  Loaded {len(our_data)} records")
    
    # Create lookup dictionary for our data using (hw, tp, conc) as key
    our_data_lookup = {}
    for record in our_data:
        key = (record['hw'], record['tp'], record['conc'])
        our_data_lookup[key] = record
    
    print(f"\nCreated lookup table with {len(our_data_lookup)} unique (hw, tp, conc) combinations")
    
    # Loop through official data and replace matching records
    replaced_count = 0
    matched_keys = []
    
    for i, official_record in enumerate(official_data):
        key = (official_record['hw'], official_record['tp'], official_record['conc'])
        
        if key in our_data_lookup:
            our_record = our_data_lookup[key]
            
            # Store old values for logging
            old_tput = official_record.get('tput_per_gpu', 'N/A')
            old_intvty = official_record.get('median_intvty', 'N/A')
            
            # Replace the values
            official_record['tput_per_gpu'] = our_record['tput_per_gpu']
            official_record['median_intvty'] = our_record['median_intvty']
            
            replaced_count += 1
            matched_keys.append({
                'index': i,
                'key': key,
                'old_tput_per_gpu': old_tput,
                'new_tput_per_gpu': our_record['tput_per_gpu'],
                'old_median_intvty': old_intvty,
                'new_median_intvty': our_record['median_intvty']
            })
    
    # Save the updated data
    if output_file is None:
        output_file = official_file
    
    print(f"\n{'='*80}")
    print(f"SUMMARY")
    print(f"{'='*80}")
    print(f"Total records in official data: {len(official_data)}")
    print(f"Total records in our TRT-LLM data: {len(our_data)}")
    print(f"Records replaced: {replaced_count}")
    print(f"{'='*80}")
    
    if matched_keys:
        print(f"\nMatched records:")
        print(f"{'-'*80}")
        for match in matched_keys:
            print(f"  Record {match['index']}: hw={match['key'][0]}, tp={match['key'][1]}, conc={match['key'][2]}")
            print(f"    tput_per_gpu: {match['old_tput_per_gpu']:.2f} -> {match['new_tput_per_gpu']:.2f}")
            print(f"    median_intvty: {match['old_median_intvty']:.2f} -> {match['new_median_intvty']:.2f}")
            print()
    
    print(f"Saving updated data to: {output_file}")
    save_json(output_file, official_data)
    print(f"✓ Successfully saved updated data")
    
    return replaced_count

def main():
    # Define file paths
    official_file = Path("official_data/agg_gptoss_1k1k.json")
    our_file = Path("our_data_gptoss/agg_gptoss_1k1k_trtllm.json")
    output_file = Path("official_data/agg_gptoss_1k1k_merged.json")  # Save to new file by default
    
    # Check if files exist
    if not official_file.exists():
        print(f"Error: Official data file not found: {official_file}")
        sys.exit(1)
    
    if not our_file.exists():
        print(f"Error: Our TRT-LLM data file not found: {our_file}")
        sys.exit(1)
    
    # Run the merge
    replaced_count = insert_our_data(official_file, our_file, output_file)
    
    print(f"\n✓ Merge complete! {replaced_count} records were updated.")
    print(f"✓ Output saved to: {output_file}")
    print(f"\nTo use the merged data, you can:")
    print(f"  1. Review the changes in: {output_file}")
    print(f"  2. If satisfied, replace the original: cp {output_file} {official_file}")

if __name__ == "__main__":
    main()

