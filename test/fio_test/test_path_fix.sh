#!/bin/bash

# Test script to verify the path fix works

echo "Testing path fix..."

# Test with absolute path
base_output_dir="/home/chanseo/test_path_fix_output"
test_id="_dev_cas1-1_iodepth1_jobs1"
output_dir="$base_output_dir/$test_id"
log_file="$output_dir/${test_id}.log"

echo "Base output dir: $base_output_dir"
echo "Test ID: $test_id"
echo "Output dir: $output_dir"
echo "Log file: $log_file"

# Create output directory
mkdir -p "$output_dir"

# Test FIO command
fio_cmd="fio --name=test --filename=/dev/cas1-1 --rw=randread --bs=64k --direct=1 \
         --ioengine=libaio --iodepth=1 --size=100M --time_based --numjobs=1 \
         --runtime=5 --group_reporting --output-format=json \
         --write_bw_log=$output_dir/${test_id} \
         --write_lat_log=$output_dir/${test_id} \
         --log_avg_msec=100 \
         --status-interval=1"

echo "Running FIO command..."
sudo $fio_cmd > $log_file 2>&1
fio_exit_code=$?

echo "FIO exit code: $fio_exit_code"

# Fix file ownership
sudo chown -R chanseo:chanseo "$output_dir" 2>/dev/null

# Check results
echo "Checking results in: $output_dir"
ls -la "$output_dir"

if [ -f "${output_dir}/${test_id}_bw.1.log" ]; then
    echo "✅ Bandwidth log created: $(wc -l < "${output_dir}/${test_id}_bw.1.log") lines"
else
    echo "❌ Bandwidth log not created"
fi

if [ -f "${output_dir}/${test_id}_lat.1.log" ]; then
    echo "✅ Latency log created: $(wc -l < "${output_dir}/${test_id}_lat.1.log") lines"
else
    echo "❌ Latency log not created"
fi

# Extract IOPS
if command -v jq >/dev/null 2>&1; then
    iops=$(jq -r '.jobs[0].read.iops // 0' "$log_file" 2>/dev/null)
    echo "✅ IOPS extracted: $iops"
else
    echo "❌ jq not available"
fi

echo "Test completed!"
