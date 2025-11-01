#!/bin/bash

# Debug script to test FIO functionality

echo "Testing FIO functionality with current setup..."

# Test basic FIO command
test_id="_dev_cas1-1_iodepth2_jobs4"
output_dir="/home/chanseo/test_fio_debug"
log_file="$output_dir/${test_id}.log"

# Create output directory
mkdir -p "$output_dir"

echo "Output directory: $output_dir"
echo "Log file: $log_file"

# Test FIO command
fio_cmd="fio --name=test --filename=/dev/cas1-1 --rw=randread --bs=64k --direct=1 \
         --ioengine=libaio --iodepth=2 --size=100M --time_based --numjobs=4 \
         --runtime=10 --group_reporting --output-format=json \
         --write_bw_log=$output_dir/${test_id} \
         --write_lat_log=$output_dir/${test_id} \
         --log_avg_msec=100 \
         --status-interval=1"

echo "Running FIO command:"
echo "$fio_cmd"

# Run FIO
$fio_cmd > $log_file 2>&1
fio_exit_code=$?

echo "FIO exit code: $fio_exit_code"

# Check results
echo "Checking results..."
if [ -f "$log_file" ]; then
    echo "Log file created: $(wc -c < "$log_file") bytes"
    echo "First 10 lines of log:"
    head -10 "$log_file"
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

echo "Test completed"
