#!/bin/bash

# Configuration files and paths
ENGINE_SRC="/home/chanseo/open-cas-linux/ocf/src/engine/engine_fast.c"
REBUILD_SCRIPT="/home/chanseo/open-cas-linux/rebuild.sh"
TEARDOWN_SCRIPT="/home/chanseo/shell/teardown_opencas_pmem.sh"
CONNECT_RDMA_SCRIPT="/home/chanseo/shell/connect-rdma.sh"
SETUP_OPENCAS_SCRIPT="/home/chanseo/shell/setup_opencas_pmem.sh"
RESULT_DIR="/home/chanseo/results_ideal_ratio_pmem"
LOG_FILE="$RESULT_DIR/test_progress.log"
PID_FILE="$RESULT_DIR/test.pid"
PROGRESS_FILE="$RESULT_DIR/progress.txt"

# Test parameters
devices=("/dev/cas1-1")
iodepths=(1)
jobnums=(1 )
block_size="64k"
test_time=15
output_file="$RESULT_DIR/ideal_ratio_results.csv"

# Calculate total number of tests
total_tests=$((${#devices[@]} * ${#iodepths[@]} * ${#jobnums[@]} * 3))  # *3 because each combination needs 3 tests

# Create results directory and initialize log file
mkdir -p "$RESULT_DIR"
echo $$ > "$PID_FILE"
echo "0/$total_tests" > "$PROGRESS_FILE"
echo "=== Test Started at $(date) ===" > "$LOG_FILE"

# Create CSV header
echo "Device,IOdepth,Jobnum,Caching IOPS,Backing IOPS,Ideal Split Ratio,Ideal Split Ratio IOPS" > "$output_file"

# Progress tracking
current_test=0
update_progress() {
    current_test=$((current_test + 1))
    echo "$current_test/$total_tests" > "$PROGRESS_FILE"
}

# Logging function
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to modify split ratio and modeling parameters in engine_fast.c
modify_engine_params() {
    local ratio=$1
    local cache_iops_val=$2
    local backend_iops_val=$3
    log_msg "Modifying split ratio to $ratio, cache_iops to $cache_iops_val, backend_iops to $backend_iops_val"
    sudo sed -i -E "s/(split_ratio[[:space:]]*=[[:space:]]*)[0-9]+;/\1$ratio;/" "$ENGINE_SRC"
    sudo sed -i -E "s/(cache_iops[[:space:]]*=[[:space:]]*)[0-9]+;/\1$cache_iops_val;/" "$ENGINE_SRC"
    sudo sed -i -E "s/(backend_iops[[:space:]]*=[[:space:]]*)[0-9]+;/\1$backend_iops_val;/" "$ENGINE_SRC"
}

# Function to rebuild and setup OpenCAS
rebuild_setup() {
    log_msg "Tearing down OpenCAS..."
    sudo "$TEARDOWN_SCRIPT" > /dev/null 2>&1

    log_msg "Rebuilding..."
    cd /home/chanseo/open-cas-linux
    sudo "$REBUILD_SCRIPT" > /dev/null 2>&1 || { log_msg "❌ Build failed"; return 1; }
    cd /home/chanseo

    log_msg "Connecting RDMA..."
    sudo "$CONNECT_RDMA_SCRIPT" > /dev/null 2>&1

    log_msg "Setting up OpenCAS..."
    sudo "$SETUP_OPENCAS_SCRIPT" > /dev/null 2>&1
}

# Function to clean IOPS value
clean_iops() {
    local raw_iops=$1
    # Remove any commas, convert scientific notation, and round to integer
    echo "$raw_iops" | tr -d ',' | awk '{printf "%.0f\n", $1}'
}

# Function to run FIO test and get IOPS
run_fio_test() {
    local device=$1
    local iodepth=$2
    local jobnum=$3

    # Warmup
    log_msg "Running warmup..."
    fio --name=warmup --filename=$device --rw=write --bs=4k --direct=1 \
        --ioengine=libaio --iodepth=32 --size=1G --numjobs=1 --runtime=$test_time \
        --group_reporting --output-format=json > /dev/null 2>&1

    sleep 5

    # Flush cache and reset stats
    log_msg "Flushing cache and resetting stats..."
    sudo casadm -F -i 1 > /dev/null 2>&1
    # sudo dmesg -c > /dev/null 2>&1
    sudo casadm -Z -i 1 > /dev/null 2>&1

    sleep 5

    # If modeling is enabled, touch the flag file right before the test
    if [ "$MODELING_ENABLE" = "1" ]; then
        touch /tmp/modeling_enable
    fi
    # Run actual test
    log_msg "Running FIO test..."
    local fio_output=$(fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
                          --ioengine=libaio --iodepth=$iodepth --size=1G --time_based --numjobs=$jobnum \
                          --runtime=$test_time --group_reporting --output-format=json 2>/dev/null)
    # Extract and clean IOPS value
    local raw_iops=$(echo "$fio_output" | jq '.jobs[] | .read.iops')
    clean_iops "$raw_iops"
}

# Cleanup function
cleanup() {
    log_msg "Received termination signal. Cleaning up..."
    rm -f "$PID_FILE"
    rm -f "$PROGRESS_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main test loop
for device in "${devices[@]}"; do
    for iodepth in "${iodepths[@]}"; do
        for jobnum in "${jobnums[@]}"; do
            log_msg "==================================================="
            log_msg "Testing with Job=$jobnum IOdepth=$iodepth"
            
            # Test with 100% cache ratio
            log_msg "[1/4] Testing with 100% cache ratio..."
            rm -f /tmp/modeling_enable
            modify_engine_params 100 0 0
            rebuild_setup
            cache_iops=$(run_fio_test "$device" "$iodepth" "$jobnum")
            log_msg "Cache IOPS: $cache_iops"
            update_progress
            
            # Test with 0% cache ratio
            log_msg "[2/4] Testing with 0% cache ratio..."
            rm -f /tmp/modeling_enable
            modify_engine_params 0 0 0
            rebuild_setup
            backing_iops=$(run_fio_test "$device" "$iodepth" "$jobnum")
            log_msg "Backing IOPS: $backing_iops"
            update_progress
            
            # Calculate ideal ratio
            if [ "$cache_iops" -gt 0 ] && [ "$backing_iops" -gt 0 ]; then
                ideal_ratio=$(echo "scale=0; ($cache_iops * 100) / ($cache_iops + $backing_iops)" | bc)
            else
                exit 1;
            fi
            log_msg "[3/4] Calculated ideal ratio: $ideal_ratio"
            
            # Test with ideal ratio
            log_msg "[4/4] Testing with ideal ratio ($ideal_ratio)..."
            MODELING_ENABLE=1
            modify_engine_params $ideal_ratio $cache_iops $backing_iops
            sudo dmesg -c > /dev/null 2>&1
            rebuild_setup
            ideal_iops=$(run_fio_test "$device" "$iodepth" "$jobnum")
            MODELING_ENABLE=0
            log_msg "Ideal ratio IOPS: $ideal_iops"
            update_progress
            
            # Save results
            echo "$device,$iodepth,$jobnum,$cache_iops,$backing_iops,$ideal_ratio,$ideal_iops" >> "$output_file"
            log_msg "Results saved for current configuration"
        done
    done
done

log_msg "🎉 All tests completed! Results saved in $output_file"
log_msg "=== Test Completed at $(date) ==="

# Cleanup at the end
cleanup 