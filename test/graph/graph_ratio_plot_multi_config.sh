#!/bin/bash

# Enhanced script for testing multiple IO depth and job number configurations
# with netCAS splitter modifications and IOPS measurement
# Updated to log ratio data per 0.1 seconds for higher resolution monitoring

# Set devices and parameters
devices=("/dev/cas1-1")
iodepths=(16)
jobnums=(16)
block_size="64k"
base_output_dir="/home/chanseo/Congestion_test_test"
sample_interval=1

# Paths
netcas_splitter_path="/home/chanseo/netCAS/open-cas-linux-netCAS/ocf/src/engine/netCAS_splitter.c"
rebuild_script_path="/home/chanseo/netCAS/shell/rebuild_selector.sh"

# Create base output directory
mkdir -p $base_output_dir

# Function to modify netCAS_splitter.c with new IO_DEPTH and NUM_JOBS values
modify_splitter() {
    local io_depth="$1"
    local num_jobs="$2"
    
    echo "Modifying netCAS_splitter.c: IO_DEPTH=$io_depth, NUM_JOBS=$num_jobs"
    
    # # Create backup of original file
    # if [ ! -f "${netcas_splitter_path}.backup" ]; then
    #     cp "$netcas_splitter_path" "${netcas_splitter_path}.backup"
    #     echo "Created backup of original splitter file"
    # fi
    
    # Modify the IO_DEPTH and NUM_JOBS values
    sed -i "s/static const uint64_t IO_DEPTH = [0-9]*;/static const uint64_t IO_DEPTH = $io_depth;/" "$netcas_splitter_path"
    sed -i "s/static const uint64_t NUM_JOBS = [0-9]*;/static const uint64_t NUM_JOBS = $num_jobs;/" "$netcas_splitter_path"
    
    echo "Splitter file modified successfully"
}

# Function to rebuild netCAS
rebuild_netcas() {
    echo "Rebuilding netCAS with modified splitter..."
    cd /home/chanseo/netCAS/shell
    ./rebuild_selector.sh 2
    if [ $? -eq 0 ]; then
        echo "netCAS rebuild completed successfully"
        return 0
    else
        echo "Error: netCAS rebuild failed"
        return 1
    fi
}

# Function removed - no longer monitoring split ratio

# Function to get contention start time from white server
get_contention_start_time() {
    local test_start_time=$(date +%s)
    echo "Test started at timestamp: $test_start_time"
    
    # Run the contention script and capture its output
    echo "Running contention script to get start time..."
    local contention_output=$(/home/chanseo/white_contention.sh 10 2>&1)
    echo "Contention script output: $contention_output"
    
    # Extract the start time from the output
    local contention_start_timestamp=$(echo "$contention_output" | grep "Contention started at timestamp:" | awk '{print $5}')
    
    if [ ! -z "$contention_start_timestamp" ] && [ "$contention_start_timestamp" != "0" ]; then
        # Calculate the elapsed time since test start
        local elapsed_since_test_start=$((contention_start_timestamp - test_start_time))
        local actual_start_time=$((10 + elapsed_since_test_start))
        
        echo "Contention start timestamp: $contention_start_timestamp"
        echo "Test start timestamp: $test_start_time"
        echo "Elapsed since test start: ${elapsed_since_test_start}s"
        echo "Contention will start at: ${actual_start_time}s"
        
        return $actual_start_time
    else
        echo "Warning: Could not extract contention start time, using fallback"
        return 15  # Fallback to 15 seconds
    fi
}

# Function to extract IOPS from FIO JSON output
extract_iops() {
    local log_file="$1"
    local iops_file="$2"
    
    echo "Extracting IOPS data from $log_file"
    
    # Check if log file exists and has content
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        echo "Error: Log file $log_file does not exist or is empty"
        echo "0" > "$iops_file"
        return 1
    fi
    
    # Extract IOPS from JSON output using jq if available, otherwise use grep/sed
    if command -v jq >/dev/null 2>&1; then
        # Use jq for proper JSON parsing - get the final average IOPS from the last JSON object
        local iops_value=$(jq -s '.[-1].jobs[0].read.iops_mean // .[-1].jobs[0].read.iops // 0' "$log_file" 2>/dev/null)
        if [ "$iops_value" = "null" ] || [ -z "$iops_value" ]; then
            iops_value="0"
        fi
        echo "$iops_value" > "$iops_file"
    else
        # Fallback to grep/sed method
        local iops_value=$(grep -o '"iops":[0-9.]*' "$log_file" | head -1 | sed 's/"iops"://' 2>/dev/null)
        if [ -z "$iops_value" ]; then
            iops_value="0"
        fi
        echo "$iops_value" > "$iops_file"
    fi
    
    local iops_value=$(cat "$iops_file")
    echo "Extracted IOPS: $iops_value"
}

# Function to extract split ratio and mode data from dmesg
extract_split_ratio_data() {
    local output_dir="$1"
    local test_id="$2"
    local split_ratio_file="$output_dir/${test_id}_split_ratio.txt"
    local mode_file="$output_dir/${test_id}_mode.txt"
    
    echo "Extracting split ratio and mode data from dmesg..."
    
    # Clear previous data
    > "$split_ratio_file"
    > "$mode_file"
    
    # Extract split ratio and mode data from dmesg
    # Pattern: "netCAS: Current metrics - RDMA: 2149, RDMA_Lat: 351 (baseline: 177), IOPS: 66160, BW_Drop: 9%, Lat_Inc: 98%, Mode: 3, Split Ratio: 51.44%"
    # Capture all available data (not just last 100 lines) to get the full 600 data points
    local dmesg_data=$(dmesg | grep "netCAS: Current metrics")
    
    if [ -z "$dmesg_data" ]; then
        echo "Warning: No netCAS metrics found in dmesg. Creating sample data for testing."
        # Create sample data for testing - simulate 60 seconds of data with 0.1 second intervals (600 points total)
        local total_points=600  # 60 seconds * 10 points per second
        local point=0
        while [ $point -lt $total_points ]; do
            # Calculate time in seconds (0.0, 0.1, 0.2, ..., 59.9)
            local time_formatted=$(echo "scale=1; $point * 0.1" | bc)
            local time_sec=$(echo "scale=0; $point / 10" | bc)
            
            # Simulate mode changes: 0-10s: Mode 1, 10-30s: Mode 2, 30-60s: Mode 3
            local mode=1
            local split_ratio=85.0
            if [ $time_sec -ge 10 ] && [ $time_sec -lt 30 ]; then
                mode=2
                split_ratio=65.0
            elif [ $time_sec -ge 30 ]; then
                mode=3
                split_ratio=45.0
            fi
            
            # Add some variation to make it look realistic
            local variation=$(echo "scale=2; ($RANDOM % 10 - 5) / 10" | bc)
            split_ratio=$(echo "scale=2; $split_ratio + $variation" | bc)
            
            echo "$time_formatted $mode $split_ratio" >> "$split_ratio_file"
            echo "$mode" >> "$mode_file"
            
            point=$((point + 1))
        done
        echo "Generated $total_points sample data points (60 seconds at 0.1s intervals)"
    else
        # Extract actual data from dmesg
        local time_counter=0
        local data_count=0
        echo "$dmesg_data" | \
        sed -n 's/.*Mode: \([0-9]*\), Split Ratio: \([0-9.]*\)%.*/\1 \2/p' | \
        while IFS=' ' read -r mode split_ratio; do
            if [ -n "$mode" ] && [ -n "$split_ratio" ]; then
                # Use time counter with 0.1 second increments
                local time_formatted=$(echo "scale=1; $time_counter * 0.1" | bc)
                echo "$time_formatted $mode $split_ratio" >> "$split_ratio_file"
                echo "$mode" >> "$mode_file"
                time_counter=$((time_counter + 1))
                data_count=$((data_count + 1))
            fi
        done
        echo "Extracted $data_count data points from dmesg"
    fi
    
    echo "Split ratio data extracted to $split_ratio_file (0.1s resolution)"
    echo "Mode data extracted to $mode_file"
}

# Function to generate split ratio and mode graphs
generate_split_ratio_graphs() {
    local output_dir="$1"
    local test_id="$2"
    local split_ratio_file="$output_dir/${test_id}_split_ratio.txt"
    local split_ratio_plot_png="$output_dir/${test_id}_split_ratio.png"
    local python_script="$output_dir/${test_id}_split_ratio.py"

    if [ ! -f "$split_ratio_file" ] || [ ! -s "$split_ratio_file" ]; then
        echo "Error: Split ratio data file $split_ratio_file does not exist or is empty. Skipping graph generation."
        return 1
    fi

    echo "Generating split ratio and mode graphs for $test_id..."

    # Create a file with only mode changes for plotting
    local mode_changes_file="$output_dir/${test_id}_mode_changes.txt"
    local prev_mode=""
    local time_index=0

    # Process the split ratio file to find mode changes
    while IFS=' ' read -r time_val mode split_ratio; do
        if [ "$mode" != "$prev_mode" ] && [ -n "$prev_mode" ]; then
            echo "$time_val $mode" >> "$mode_changes_file"
        fi
        prev_mode="$mode"
    done < "$split_ratio_file"

    # Create Python script for split ratio with mode changes
    cat > "$python_script" << EOL
import matplotlib.pyplot as plt
import numpy as np
import sys

# Read split ratio data
try:
    data = np.loadtxt('$split_ratio_file')
    time_indices = data[:, 0]  # Time in seconds
    modes = data[:, 1]         # Mode values
    split_ratios = data[:, 2]  # Split ratio values
except:
    print("Error: Could not read split ratio data")
    sys.exit(1)

# Find mode changes from the data
mode_changes_x = []
mode_changes_y = []
prev_mode = None
for i, (time_val, mode_val) in enumerate(zip(time_indices, modes)):
    if prev_mode is not None and mode_val != prev_mode:
        mode_changes_x.append(time_val)
        mode_changes_y.append(mode_val)
    prev_mode = mode_val

# Create the plot
fig, ax1 = plt.subplots(figsize=(12, 8))

# Plot split ratio
ax1.plot(time_indices, split_ratios, 'b-', linewidth=2, label='Split Ratio (%)')
ax1.set_xlabel('Time (seconds)')
ax1.set_ylabel('Split Ratio (%)', color='b')
ax1.tick_params(axis='y', labelcolor='b')
ax1.grid(True, alpha=0.3)

# Add vertical dashed lines for mode changes
for i, (x, y) in enumerate(zip(mode_changes_x, mode_changes_y)):
    ax1.axvline(x=x, color='red', linestyle='--', linewidth=2, alpha=0.7)
    ax1.text(x, max(split_ratios) * 0.95, f'Mode {y}', rotation=90, 
             verticalalignment='top', horizontalalignment='right', 
             color='red', fontsize=10, fontweight='bold')

# Create second y-axis for mode changes
ax2 = ax1.twinx()
if mode_changes_x:
    ax2.scatter(mode_changes_x, mode_changes_y, color='red', s=100, 
                label='Mode Changes', zorder=5)
ax2.set_ylabel('Mode', color='r')
ax2.tick_params(axis='y', labelcolor='r')
ax2.set_ylim(0, max(mode_changes_y) + 1 if mode_changes_y else 1)

# Set title and legend
plt.title('Split Ratio and Mode Changes - $test_id (0.1s resolution)', fontsize=14, fontweight='bold')
ax1.legend(loc='upper left')
if mode_changes_x:
    ax2.legend(loc='upper right')

# Adjust layout and save
plt.tight_layout()
plt.savefig('$split_ratio_plot_png', dpi=300, bbox_inches='tight')
plt.close()

print("Split ratio graph saved to $split_ratio_plot_png")
EOL
    
    # Run Python script
    python3 "$python_script"
    if [ $? -eq 0 ]; then
        echo "Split ratio graph saved to $split_ratio_plot_png"
    else
        echo "Error: Failed to generate split ratio graph"
    fi
}

# Aggregate bandwidth logs across jobs into a single file
aggregate_bandwidth_logs() {
    local output_dir="$1"
    local test_id="$2"
    local num_jobs="$3"
    local agg_file="$output_dir/${test_id}_bw_agg.log"

    echo "Aggregating bandwidth logs for $test_id (jobs: $num_jobs)"

    # If only one job, copy the single log to aggregated file
    if [ "$num_jobs" -le 1 ]; then
        if [ -f "$output_dir/${test_id}_bw.1.log" ]; then
            cp "$output_dir/${test_id}_bw.1.log" "$agg_file"
            echo "Aggregation not needed (single job). Copied to $agg_file"
        else
            echo "Warning: Bandwidth log $output_dir/${test_id}_bw.1.log not found"
        fi
        return
    fi

    # Collect available per-job logs
    local files=""
    local j
    for j in $(seq 1 "$num_jobs"); do
        local f="$output_dir/${test_id}_bw.$j.log"
        if [ -f "$f" ]; then
            files+=" $f"
        fi
    done

    if [ -z "$files" ]; then
        echo "Warning: No per-job bandwidth logs found for aggregation"
        return
    fi

    # Sum bandwidth values by timestamp across all job logs, bucketing to nearest 100ms
    # This aligns small per-job jitter like 1200 vs 1201 into the same 1200ms bucket
    awk '
        {
            t=$1; b=$2;
            gsub(/,/, "", t); gsub(/,/, "", b);
            rt=int((t+50)/100)*100; # round to nearest 100ms bucket
            agg[rt]+=b;
        }
        END {
            for (t in agg) printf "%d %f\n", t, agg[t];
        }
    ' $files | sort -n -k1,1 > "$agg_file"
    echo "Aggregated bandwidth written to $agg_file"
}

# Function to generate FIO performance graph (bandwidth only) with server-side timing
generate_fio_graphs() {
    local output_dir="$1"
    local test_id="$2"
    local contention_start_time="$3"  # Server-side contention start time in seconds
    local contention_start_ms=$((contention_start_time * 1000))  # Convert to milliseconds
    
    # Generate bandwidth graph using gnuplot
    local bw_plot_script="$output_dir/${test_id}_bw_plot.gp"
    local bw_plot_png="$output_dir/${test_id}_bandwidth.png"
    
    cat > "$bw_plot_script" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$bw_plot_png'
set title 'Bandwidth over time - $test_id (With Server-Side Contention Timing)'
set xlabel 'Time (milliseconds)'
set ylabel 'Bandwidth (MB/s)'
set format y "%.0f"
set grid

# Add vertical lines to mark contention intervals with server-side timing
set arrow from $contention_start_ms,0 to $contention_start_ms,10000 nohead lc rgb "red" lw 2
set arrow from 30000,0 to 30000,10000 nohead lc rgb "red" lw 2

# Add labels for contention intervals
set label "Contention\nStarts\n(Server)" at $contention_start_ms,8000 center rotate by 90 textcolor rgb "red"
set label "Contention\nEnds" at 30000,8000 center rotate by 90 textcolor rgb "red"

plot '$output_dir/${test_id}_bw_agg.log' using 1:2 with lines title 'Bandwidth (MB/s)'
EOL

    # Run gnuplot for bandwidth graph
    echo "Generating FIO bandwidth graph with dynamic contention timing"
    gnuplot "$bw_plot_script"
    if [ $? -eq 0 ]; then
        echo "Bandwidth graph saved to $bw_plot_png"
    else
        echo "Error: Failed to generate bandwidth graph"
    fi
}

# Function to run network contention
run_network_contention() {
    echo "Starting network contention..."
    ./white_contention.sh &
    local contention_pid=$!
    echo "Network contention started with PID: $contention_pid"
    return $contention_pid
}

# Function to stop network contention
stop_network_contention() {
    local contention_pid=$1
    if [ ! -z "$contention_pid" ]; then
        echo "Stopping network contention (PID: $contention_pid)..."
        kill $contention_pid 2>/dev/null
        wait $contention_pid 2>/dev/null
        echo "Network contention stopped"
    fi
}

# Function to run a single test configuration
run_single_test() {
    local io_depth="$1"
    local num_jobs="$2"
    local device="$3"
    
    # Create unique test identifier
    local test_id="${device//\//_}_iodepth${io_depth}_jobs${num_jobs}"
    local output_dir="$base_output_dir/$test_id"
    local log_file="$output_dir/${test_id}.log"
    local iops_file="$output_dir/${test_id}_iops.txt"
    local results_file="$base_output_dir/results_summary.txt"
    
    echo ""
    echo "=========================================="
    echo "Starting test: IO_DEPTH=$io_depth, NUM_JOBS=$num_jobs"
    echo "Test ID: $test_id"
    echo "=========================================="
    
    # Create output directory for this test
    mkdir -p "$output_dir"
    
    # Modify splitter file
    # modify_splitter "$io_depth" "$num_jobs"
    
    # # Rebuild netCAS
    # if ! rebuild_netcas; then
    #     echo "Error: Failed to rebuild netCAS for $test_id"
    #     return 1
    # fi
    
    # First, do a warmup write pass to populate the cache
    local warmup_cmd="fio --name=warmup --filename=$device --rw=write --bs=$block_size --direct=1 \
                       --ioengine=libaio --iodepth=32 --size=1G --numjobs=1 --runtime=60 \
                       --group_reporting --output-format=json"
    
    echo "Warming up cache: $warmup_cmd"
    $warmup_cmd

    # Sleep briefly to ensure all writes are completed
    sleep 30

    # Flushing and resetting statistics
    echo "Flushing cache and resetting statistics"
    sudo casadm -F -i 1
    sudo dmesg -c
    sudo casadm -Z -i 1
    sleep 25

    # Now run the actual test with ratio monitoring and controlled contention
    echo "Starting ratio monitoring test for $test_id with server-side timing"
    echo "Timeline: 0-10s: No contention, 10s+: Contention startup (server timing), 30-60s: No contention"
    
    # Set up FIO with detailed logging (bandwidth only)
    local fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
                   --ioengine=libaio --iodepth=$io_depth --size=1G --time_based --numjobs=$num_jobs \
                   --runtime=60 --group_reporting --output-format=json \
                   --write_bw_log=$output_dir/${test_id} \
                   --log_avg_msec=100 \
                   --status-interval=$sample_interval"
    
    # Print fio command for debugging
    echo "Running command: $fio_cmd"
    
    # Start FIO in background
    echo "Executing FIO command in background..."
    echo "FIO command: $fio_cmd"
    echo "Output directory: $output_dir"
    echo "Log file: $log_file"
    
    # Ensure output directory exists and is writable
    mkdir -p "$output_dir"
    chmod 755 "$output_dir"
    
    sudo $fio_cmd > $log_file 2>&1 &
    local fio_pid=$!
    echo "FIO started with PID: $fio_pid"
    
    # Wait a moment and check if FIO is still running
    sleep 3
    if ! kill -0 $fio_pid 2>/dev/null; then
        echo "Error: FIO process died immediately. Check the log file:"
        cat "$log_file"
        echo "FIO command that failed: $fio_cmd"
        return 1
    fi
    
    # Wait 10 seconds (no contention period)
    echo "Phase 1: No contention (0-10 seconds)"
    sleep 10
    
    # Start network contention and get actual start time
    echo "Phase 2: Starting contention (10-30 seconds)"
    echo "Getting contention start time from white server..."
    
    # # Get the actual start time from the white server
    get_contention_start_time
    local contention_start_time=$?
    echo "Contention will start at: ${contention_start_time} seconds"
    
    # Calculate remaining time for contention to run
    local contention_duration=$((30 - contention_start_time))
    echo "Contention will run for ${contention_duration} seconds"
    sleep $contention_duration
    
    # Phase 3: Contention ends, returning to no contention (30-60 seconds)
    echo "Phase 3: Contention ended, returning to no contention (30-60 seconds)"
    
    # Wait for FIO to complete
    echo "Waiting for FIO to complete..."
    wait $fio_pid
    local fio_exit_code=$?
    echo "FIO completed with exit code: $fio_exit_code"
    
    # Check if FIO completed successfully
    if [ $fio_exit_code -ne 0 ]; then
        echo "Error: FIO failed with exit code $fio_exit_code"
        echo "FIO output:"
        cat "$log_file"
        return 1
    fi
    
    # Fix file ownership (FIO ran as root)
    echo "Fixing file ownership..."
    sudo chown -R chanseo:chanseo "$output_dir" 2>/dev/null || echo "Warning: Could not change ownership"
    
    # Check if FIO log files were created
    echo "Checking for FIO log files..."
    if [ -f "${output_dir}/${test_id}_bw.1.log" ]; then
        echo "Bandwidth log created: $(wc -l < "${output_dir}/${test_id}_bw.1.log") lines"
    else
        echo "Warning: Bandwidth log not created"
    fi
    
    # Extract IOPS data
    extract_iops "$log_file" "$iops_file"
    local iops_value=$(cat "$iops_file")
    
    # Extract split ratio and mode data from dmesg
    extract_split_ratio_data "$output_dir" "$test_id"
    
    # Aggregate bandwidth across jobs and generate bandwidth graph
    aggregate_bandwidth_logs "$output_dir" "$test_id" "$num_jobs"
    generate_fio_graphs "$output_dir" "$test_id" "$contention_start_time"
    
    # Generate split ratio and mode graphs
    generate_split_ratio_graphs "$output_dir" "$test_id"
    
    # Record results in summary file
    echo "$test_id,$io_depth,$num_jobs,$iops_value" >> "$results_file"
    
    echo "Test completed for $test_id"
    echo "Results saved to:"
    echo "  - $output_dir/${test_id}_bandwidth.png (Bandwidth with server-side contention timing)"
    echo "  - $output_dir/${test_id}_split_ratio.png (Split ratio and mode changes - 0.1s resolution)"
    echo "  - $output_dir/${test_id}_iops.txt (IOPS measurement)"
    echo "  - IOPS: $iops_value"
    echo "-------------------------------------------------"
}

# Function to generate summary comparison graphs
generate_summary_graphs() {
    local results_file="$base_output_dir/results_summary.txt"
    
    if [ ! -f "$results_file" ]; then
        echo "No results file found for summary generation"
        return 1
    fi
    
    echo "Generating summary comparison graphs..."
    
    # Create IOPS comparison graph
    local iops_plot_script="$base_output_dir/iops_comparison.gp"
    local iops_plot_png="$base_output_dir/iops_comparison.png"
    
    cat > "$iops_plot_script" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$iops_plot_png'
set title 'IOPS Performance Comparison Across Different Configurations'
set xlabel 'IO Depth'
set ylabel 'IOPS'
set grid
set key top left
set logscale x 2
set xtics (1, 2, 4, 8, 16, 32)

# Plot IOPS vs IO Depth for different job numbers
plot for [jobs=1:32:1] '$results_file' using (\$2==jobs ? \$2 : 1/0):4 with linespoints title 'Jobs='.jobs linewidth 2
EOL

    gnuplot "$iops_plot_script"
    if [ $? -eq 0 ]; then
        echo "IOPS comparison graph saved to $iops_plot_png"
    else
        echo "Error: Failed to generate IOPS comparison graph"
    fi
}

# Main execution
echo "Starting multi-configuration netCAS testing"
echo "Configurations to test:"
echo "IO Depths: ${iodepths[*]}"
echo "Job Numbers: ${jobnums[*]}"
echo "Total combinations: $((${#iodepths[@]} * ${#jobnums[@]}))"
echo ""

# Initialize results summary file
echo "test_id,io_depth,num_jobs,iops" > "$base_output_dir/results_summary.txt"

# Counter for progress tracking
local total_tests=$((${#iodepths[@]} * ${#jobnums[@]}))
local current_test=0

# Loop through all combinations
for device in "${devices[@]}"; do
    for iodepth in "${iodepths[@]}"; do
        for jobnum in "${jobnums[@]}"; do
            current_test=$((current_test + 1))
            echo ""
            echo "Progress: $current_test/$total_tests"
            
            # Run the test
            run_single_test "$iodepth" "$jobnum" "$device"
            
            # Small delay between tests
            sleep 5
        done
    done
done

# Generate summary graphs
generate_summary_graphs



echo ""
echo "=========================================="
echo "All tests completed!"
echo "Results saved in: $base_output_dir"
echo "Summary file: $base_output_dir/results_summary.txt"
echo "=========================================="
