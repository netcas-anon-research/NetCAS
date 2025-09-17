#!/bin/bash

set -e  # Exit on any error

# Configuration
DEVICE="/dev/cas1-1"
BLOCK_SIZE="64k"
IO_DEPTH=16
NUM_JOBS=16
RUNTIME=30
TEST_SIZE="1G"
ITERATIONS=1

# Resolve directories relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Output directories
CPU_PROFILING_DIR="$SCRIPT_DIR"
RESULTS_DIR="$CPU_PROFILING_DIR/cpu_test_results"
ANALYZE_PY="$SCRIPT_DIR/analyze_netcas_cpu.py"
ANALYZE_SH="$SCRIPT_DIR/analyze_netcas.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --netcas-only     Test only netCAS implementation"
    echo "  --opencas-only    Test only openCAS implementation"
    echo "  --mf-only         Test only MF implementation"
    echo "  --all             Test all three implementations (default)"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --netcas-only    # Test only netCAS"
    echo "  $0 --opencas-only   # Test only openCAS"
    echo "  $0 --mf-only        # Test only MF"
    echo "  $0 --all            # Test all implementations"
    echo ""
    echo "Note: When testing multiple implementations, the script will automatically"
    echo "switch between implementations using rebuild_selector.sh."
}

# Parse command line arguments
TEST_MODE="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --netcas-only)
            TEST_MODE="netcas"
            shift
            ;;
        --opencas-only)
            TEST_MODE="opencas"
            shift
            ;;
        --mf-only)
            TEST_MODE="mf"
            shift
            ;;
        --all)
            TEST_MODE="all"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Prepare CPU profiling root and migrate old outputs if present
prepare_cpu_profiling_dir() {
    print_status "Preparing CPU profiling directory at $CPU_PROFILING_DIR"
    mkdir -p "$CPU_PROFILING_DIR"
    mkdir -p "$RESULTS_DIR"

    # Move legacy CPU outputs into CPU_profiling if they exist at repo root
    local moved_any=0
    for d in \
        "$REPO_ROOT/cpu_test_results" \
        "$REPO_ROOT/cpu_analysis_output-netCAS" \
        "$REPO_ROOT/cpu_analysis_output-MF" \
        "$REPO_ROOT/cpu_analysis_output-comparison"; do
        if [ -e "$d" ]; then
            local base
            base=$(basename "$d")
            if [ ! -e "$CPU_PROFILING_DIR/$base" ]; then
                print_status "Moving $base to CPU_profiling/"
                mv "$d" "$CPU_PROFILING_DIR/" || true
                moved_any=1
            else
                print_warning "$base already exists under CPU_profiling, skipping move"
            fi
        fi
    done
    if [ "$moved_any" = "1" ]; then
        print_success "Existing CPU outputs moved to $CPU_PROFILING_DIR"
    fi
}

# Function to run a single test iteration
run_test_iteration() {
    local test_name="$1"
    local iteration="$2"
    local output_dir="$RESULTS_DIR/$test_name/iteration_$iteration"
    
    mkdir -p "$output_dir"
    
    print_status "Running $test_name test iteration $iteration..."
    
    # ---------------- Warmup phase (excluded from measurement) ----------------
    print_status "Warmup: sequential write to populate cache"
    fio --name=warmup_seq \
        --filename="$DEVICE" \
        --rw=write \
        --bs="$BLOCK_SIZE" \
        --direct=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --size="$TEST_SIZE" \
        --numjobs=1 \
        --group_reporting \
        --output-format=json \
        > "$output_dir/warmup_seq.log" 2>&1 || true
    
    print_status "Warmup: random write to fully heat cache"
    fio --name=warmup_rand \
        --filename="$DEVICE" \
        --rw=randwrite \
        --bs="$BLOCK_SIZE" \
        --direct=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --size="$TEST_SIZE" \
        --numjobs=1 \
        --runtime=120 \
        --time_based \
        --group_reporting \
        --output-format=json \
        > "$output_dir/warmup_rand.log" 2>&1 || true
    
    # Ensure writes are completed
    sleep 5
    
    # Flush cache and reset stats if available
    if command -v casadm >/dev/null 2>&1; then
        print_status "Flushing cache and resetting stats (casadm)"
        sudo casadm -F -i 1 || true
        sudo dmesg -c >/dev/null 2>&1 || true
        sudo casadm -Z -i 1 || true
        sleep 5
    fi
    # -------------------------------------------------------------------------
    
    # Start system monitoring in background (measurement window starts here)
    print_status "Starting system monitoring..."
    
    # Monitor CPU usage
    mpstat 1 > "$output_dir/mpstat.log" &
    local mpstat_pid=$!
    
    # Monitor disk I/O
    iostat -x 1 > "$output_dir/iostat.log" &
    local iostat_pid=$!
    
    # Monitor memory
    vmstat 1 > "$output_dir/vmstat.log" &
    local vmstat_pid=$!
    
    # Wait for monitoring to start
    sleep 2
    
    # Start perf record
    print_status "Starting perf record..."
    perf record -g -F 99 -o "$output_dir/perf.data" &
    local perf_pid=$!
    
    sleep 1
    
    # Run FIO test (measurement workload)
    print_status "Running FIO test..."
    fio --name=test \
        --filename="$DEVICE" \
        --rw=randread \
        --bs="$BLOCK_SIZE" \
        --direct=1 \
        --ioengine=libaio \
        --iodepth="$IO_DEPTH" \
        --size="$TEST_SIZE" \
        --time_based \
        --numjobs="$NUM_JOBS" \
        --runtime="$RUNTIME" \
        --group_reporting \
        --output-format=json \
        --output="$output_dir/fio_output.json" \
        > "$output_dir/fio.log" 2>&1
    
    # Stop perf recording
    print_status "Stopping perf record..."
    kill -INT "$perf_pid" 2>/dev/null
    wait "$perf_pid" 2>/dev/null
    
    # Stop monitoring
    print_status "Stopping system monitoring..."
    kill "$mpstat_pid" "$iostat_pid" "$vmstat_pid" 2>/dev/null
    wait "$mpstat_pid" "$iostat_pid" "$vmstat_pid" 2>/dev/null 2>/dev/null
    
    # Parse FIO results
    local iops=$(jq -r '.jobs[0].read.iops' "$output_dir/fio_output.json" 2>/dev/null || echo "0")
    local bandwidth=$(jq -r '.jobs[0].read.bw' "$output_dir/fio_output.json" 2>/dev/null || echo "0")
    
    # Save results summary
    {
        echo "IOPS: $iops"
        echo "Bandwidth (KB/s): $bandwidth"
        echo "Test completed at: $(date)"
    } > "$output_dir/results.txt"
    
    print_success "Test completed: IOPS=$iops, BW=${bandwidth}KB/s"
    
    # Generate perf report
    print_status "Generating perf report..."
    perf report --stdio -i "$output_dir/perf.data" > "$output_dir/perf_report.txt" 2>/dev/null || true
    
    return 0
}

# Function to run complete test for one implementation
run_complete_test() {
    local test_name="$1"
    
    print_status "Starting complete test for: $test_name"
    print_status "Running $ITERATIONS iterations..."
    
    mkdir -p "$RESULTS_DIR/$test_name"
    
    for i in $(seq 1 $ITERATIONS); do
        if run_test_iteration "$test_name" "$i"; then
            if [ $i -lt $ITERATIONS ]; then
                print_status "Waiting 5 seconds before next iteration..."
                sleep 5
            fi
        else
            print_error "Iteration $i failed"
            return 1
        fi
    done
    
    print_success "Complete test finished for: $test_name"

    # Run analyses for each iteration and save under iteration directory
    for i in $(seq 1 $ITERATIONS); do
        local iter_dir="$RESULTS_DIR/$test_name/iteration_$i"
        if [ -d "$iter_dir" ]; then
            local out_python="$iter_dir/analysis_python"
            local out_sh="$iter_dir/analysis_sh"
            mkdir -p "$out_python" "$out_sh"

            print_status "Analyzing $test_name iteration $i (python)"
            python3 "$ANALYZE_PY" "$iter_dir" --output-dir "$out_python" --no-viz || true

            print_status "Analyzing $test_name iteration $i (shell)"
            bash "$ANALYZE_SH" "$iter_dir" --output-dir "$out_sh" || true
        fi
    done
}

# Function to generate comparison report
generate_comparison() {
    print_status "Generating comparison report..."
    
    local report_file="$RESULTS_DIR/comparison.txt"
    
    {
        echo "=== CPU Usage Comparison Report ==="
        echo "Date: $(date)"
        echo "Test Configuration:"
        echo "- Device: $DEVICE"
        echo "- Block Size: $BLOCK_SIZE"
        echo "- IO Depth: $IO_DEPTH"
        echo "- Runtime: $RUNTIME seconds"
        echo "- Iterations: $ITERATIONS"
        echo ""
        
        # netCAS results
        if [ -d "$RESULTS_DIR/netCAS" ]; then
            echo "=== netCAS Results ==="
            for i in $(seq 1 $ITERATIONS); do
                local iter_dir="$RESULTS_DIR/netCAS/iteration_$i"
                if [ -f "$iter_dir/results.txt" ]; then
                    echo "Iteration $i:"
                    cat "$iter_dir/results.txt"
                    echo ""
                fi
            done
        fi
        
        echo ""
        
        # openCAS results
        if [ -d "$RESULTS_DIR/openCAS" ]; then
            echo "=== openCAS Results ==="
            for i in $(seq 1 $ITERATIONS); do
                local iter_dir="$RESULTS_DIR/openCAS/iteration_$i"
                if [ -f "$iter_dir/results.txt" ]; then
                    echo "Iteration $i:"
                    cat "$iter_dir/results.txt"
                    echo ""
                fi
            done
        fi
        
        echo ""
        
        # MF results
        if [ -d "$RESULTS_DIR/MF" ]; then
            echo "=== MF Results ==="
            for i in $(seq 1 $ITERATIONS); do
                local iter_dir="$RESULTS_DIR/MF/iteration_$i"
                if [ -f "$iter_dir/results.txt" ]; then
                    echo "Iteration $i:"
                    cat "$iter_dir/results.txt"
                    echo ""
                fi
            done
        fi
        
        echo ""
        echo "=== Analysis Instructions ==="
        echo "1. Check perf reports in each iteration directory"
        echo "2. Compare system metrics (mpstat, iostat, vmstat) for total amounts"
        echo "3. Look for differences in CPU usage patterns"
        echo "4. Compare absolute CPU usage, memory usage, and block I/O totals"
        echo "5. Consider MF's background monitoring thread impact"
    } > "$report_file"
    
    print_success "Comparison report generated: $report_file"
}

# Function to check if we have the rebuild selector script
check_rebuild_script() {
    if [ ! -f "$REPO_ROOT/shell/rebuild_selector.sh" ]; then
        print_error "rebuild_selector.sh not found under '$REPO_ROOT/shell'"
        exit 1
    fi
}

# Function to get rebuild script path
get_rebuild_script_path() {
    echo "$REPO_ROOT/shell/rebuild_selector.sh"
}

# Function to switch to netCAS implementation (option 2)
switch_to_netcas() {
    print_status "Switching to netCAS implementation..."
    
    local rebuild_script=$(get_rebuild_script_path)
    
    if [ -f "$rebuild_script" ]; then
        local netcas_option="2"
        print_status "Using option $netcas_option for netCAS implementation"
        
        print_status "Running: $rebuild_script $netcas_option"
        cd "$(dirname "$rebuild_script")"
        sudo "$(basename "$rebuild_script")" "$netcas_option"
        cd - > /dev/null
        
        print_success "Switched to netCAS implementation"
    else
        print_error "Could not find rebuild script"
        return 1
    fi
}

# Function to switch to openCAS implementation (option 1)
switch_to_opencas() {
    print_status "Switching to openCAS implementation..."
    
    local rebuild_script=$(get_rebuild_script_path)
    
    if [ -f "$rebuild_script" ]; then
        local opencas_option="1"
        print_status "Using option $opencas_option for openCAS implementation"
        
        print_status "Running: $rebuild_script $opencas_option"
        cd "$(dirname "$rebuild_script")"
        sudo "$(basename "$rebuild_script")" "$opencas_option"
        cd - > /dev/null
        
        print_success "Switched to openCAS implementation"
    else
        print_error "Could not find rebuild script"
        return 1
    fi
}

# Function to switch to MF implementation
switch_to_mf() {
    print_status "Switching to MF implementation..."
    
    local rebuild_script=$(get_rebuild_script_path)
    
    # Find which option corresponds to open-cas-linux-mf
    local mf_option=""
    if [ -f "$rebuild_script" ]; then
        # This is a simple approach - we'll need to determine the correct option
        # For now, let's assume it's option 3 (you may need to adjust this)
        mf_option="3"
        print_status "Using option $mf_option for MF implementation"
        
        print_status "Running: $rebuild_script $mf_option"
        cd "$(dirname "$rebuild_script")"
        sudo "$(basename "$rebuild_script")" "$mf_option"
        cd - > /dev/null
        
        print_success "Switched to MF implementation"
    else
        print_error "Could not find rebuild script"
        return 1
    fi
}

# Main execution
main() {
    print_status "Starting Simple CPU Test Suite"
    print_status "=============================="
    print_status "Test mode: $TEST_MODE"
    echo ""
    
    # Prepare profiling directories and migrate legacy outputs
    prepare_cpu_profiling_dir
    
    # Check if we have required tools
    if ! command -v perf >/dev/null 2>&1; then
        print_error "perf not found. Please install linux-tools-common"
        exit 1
    fi
    
    if ! command -v fio >/dev/null 2>&1; then
        print_error "fio not found. Please install fio"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq not found. Please install jq"
        exit 1
    fi
    
    # Check if we have the rebuild selector script
    check_rebuild_script
    
    case "$TEST_MODE" in
        "netcas")
            print_status "Testing netCAS implementation only..."
            # Switch to netCAS implementation first
            if switch_to_netcas; then
                print_status "Waiting 10 seconds for implementation switch to stabilize..."
                sleep 10
                run_complete_test "netCAS"
                print_success "netCAS test completed!"
            else
                print_error "Failed to switch to netCAS implementation"
                exit 1
            fi
            ;;
            
        "opencas")
            print_status "Testing openCAS implementation only..."
            # Switch to openCAS implementation first
            if switch_to_opencas; then
                print_status "Waiting 10 seconds for implementation switch to stabilize..."
                sleep 10
                run_complete_test "openCAS"
                print_success "openCAS test completed!"
            else
                print_error "Failed to switch to openCAS implementation"
                exit 1
            fi
            ;;
            
        "mf")
            print_status "Testing MF implementation only..."
            # Switch to MF implementation first
            if switch_to_mf; then
                print_status "Waiting 10 seconds for implementation switch to stabilize..."
                sleep 10
                run_complete_test "MF"
                print_success "MF test completed!"
            else
                print_error "Failed to switch to MF implementation"
                exit 1
            fi
            ;;
            
        "all")
            print_status "Testing all three implementations..."
            
            # Run netCAS test first
            print_status "Starting with netCAS test..."
            if switch_to_netcas; then
                print_status "Waiting 10 seconds for implementation switch to stabilize..."
                sleep 10
                run_complete_test "netCAS"
                
                echo ""
                print_warning "netCAS test completed. Now switching to openCAS implementation..."
                
                # Switch to openCAS implementation
                if switch_to_opencas; then
                    print_status "Waiting 10 seconds for implementation switch to stabilize..."
                    sleep 10
                    
                    # Run openCAS test
                    print_status "Starting openCAS test..."
                    run_complete_test "openCAS"
                    
                    echo ""
                    print_warning "openCAS test completed. Now switching to MF implementation..."
                    
                    # Switch to MF implementation
                    if switch_to_mf; then
                        print_status "Waiting 10 seconds for implementation switch to stabilize..."
                        sleep 10
                        
                        # Run MF test
                        print_status "Starting MF test..."
                        run_complete_test "MF"
                        
                        # Generate comparison
                        generate_comparison
                        
                        print_success "All three tests completed!"
                    else
                        print_error "Failed to switch to MF implementation"
                        exit 1
                    fi
                else
                    print_error "Failed to switch to openCAS implementation"
                    exit 1
                fi
            else
                print_error "Failed to switch to netCAS implementation"
                exit 1
            fi
            ;;
    esac
    
    print_status "Results are available in: $RESULTS_DIR"
    if [ "$TEST_MODE" = "all" ]; then
        print_status "Check the comparison report: $RESULTS_DIR/comparison.txt"
    fi
}

# Run main function
main "$@"
