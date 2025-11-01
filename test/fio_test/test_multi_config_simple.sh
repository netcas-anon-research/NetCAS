#!/bin/bash

# Simple test of the multi-config script with just one configuration

echo "Testing multi-config script with single configuration..."

# Test with just one configuration
iodepths=(2)
jobnums=(4)
devices=("/dev/cas1-1")
block_size="64k"
base_output_dir="test_multi_config_simple"
sample_interval=1

# Create base output directory
mkdir -p $base_output_dir

# Test single configuration
io_depth=2
num_jobs=4
device="/dev/cas1-1"

# Create unique test identifier
test_id="${device//\//_}_iodepth${io_depth}_jobs${num_jobs}"
output_dir="$base_output_dir/$test_id"
log_file="$output_dir/${test_id}.log"
iops_file="$output_dir/${test_id}_iops.txt"

echo "Test ID: $test_id"
echo "Output directory: $output_dir"

# Create output directory for this test
mkdir -p "$output_dir"

# Test FIO command
fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
         --ioengine=libaio --iodepth=$io_depth --size=100M --time_based --numjobs=$num_jobs \
         --runtime=10 --group_reporting --output-format=json \
         --write_bw_log=$output_dir/${test_id} \
         --write_lat_log=$output_dir/${test_id} \
         --log_avg_msec=100 \
         --status-interval=$sample_interval"

echo "Running FIO command:"
echo "$fio_cmd"

# Run FIO with sudo
sudo $fio_cmd > $log_file 2>&1
fio_exit_code=$?

echo "FIO exit code: $fio_exit_code"

# Fix file ownership
sudo chown -R chanseo:chanseo "$output_dir" 2>/dev/null || echo "Warning: Could not change ownership"

# Check results
echo "Checking results..."
if [ -f "$log_file" ]; then
    echo "Log file created: $(wc -c < "$log_file") bytes"
else
    echo "Error: Log file not created"
fi

# Check FIO log files
if [ -f "${output_dir}/${test_id}_bw.1.log" ]; then
    echo "Bandwidth log created: $(wc -l < "${output_dir}/${test_id}_bw.1.log") lines"
else
    echo "Warning: Bandwidth log not created"
fi

if [ -f "${output_dir}/${test_id}_lat.1.log" ]; then
    echo "Latency log created: $(wc -l < "${output_dir}/${test_id}_lat.1.log") lines"
else
    echo "Warning: Latency log not created"
fi

# Extract IOPS
if command -v jq >/dev/null 2>&1; then
    iops=$(jq -r '.jobs[0].read.iops // 0' "$log_file" 2>/dev/null)
    echo "Extracted IOPS: $iops"
else
    echo "jq not available, using grep..."
    iops=$(grep -o '"iops":[0-9.]*' "$log_file" | head -1 | sed 's/"iops"://' 2>/dev/null)
    echo "Extracted IOPS: $iops"
fi

echo "Test completed successfully!"
echo "Results in: $output_dir"
