#!/bin/bash

# Quick analysis script for CPU test results
# Usage: ./analyze_results.sh [results_directory]

# Resolve script directory and default results under CPU_profiling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to CPU_profiling/cpu_test_results if no argument provided
RESULTS_DIR="${1:-$SCRIPT_DIR/cpu_test_results}"

if [ ! -d "$RESULTS_DIR" ]; then
    echo "Error: Results directory '$RESULTS_DIR' not found"
    echo "Usage: $0 [results_directory]"
    exit 1
fi

echo "=== CPU Test Results Analysis ==="
echo "Results directory: $RESULTS_DIR"
echo ""

# Function to extract key metrics from perf report
analyze_perf_report() {
    local perf_file="$1"
    local test_name="$2"
    
    if [ ! -f "$perf_file" ]; then
        echo "  Perf report not found"
        return
    fi
    
    echo "  === Top CPU Consumers ==="
    
    # Extract top functions by CPU usage
    grep -A 20 "Overhead  Command  Symbol" "$perf_file" | head -25 | while read line; do
        if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[0-9]+ ]]; then
            echo "    $line"
        fi
    done
    
    echo ""
}

# Function to analyze system metrics
analyze_system_metrics() {
    local metrics_dir="$1"
    local test_name="$2"
    
    if [ ! -d "$metrics_dir" ]; then
        echo "  System metrics not found"
        return
    fi
    
    echo "  === System Metrics Summary ==="
    
    # Analyze mpstat (CPU usage)
    if [ -f "$metrics_dir/mpstat.log" ]; then
        echo "  CPU Usage (mpstat):"
        tail -10 "$metrics_dir/mpstat.log" | grep -v "Linux" | while read line; do
            if [[ "$line" =~ ^[[:space:]]*[0-9]+ ]]; then
                echo "    $line"
            fi
        done
        echo ""
    fi
    
    # Analyze iostat (disk I/O)
    if [ -f "$metrics_dir/iostat.log" ]; then
        echo "  Disk I/O (iostat):"
        tail -5 "$metrics_dir/iostat.log" | grep -v "Linux" | while read line; do
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z] ]]; then
                echo "    $line"
            fi
        done
        echo ""
    fi
}

# Analyze netCAS results
if [ -d "$RESULTS_DIR/netCAS" ]; then
    echo "=== netCAS Implementation Analysis ==="
    
    for iter_dir in "$RESULTS_DIR/netCAS"/iteration_*; do
        if [ -d "$iter_dir" ]; then
            iter_num=$(basename "$iter_dir" | sed 's/iteration_//')
            echo "Iteration $iter_num:"
            
            # Show FIO results
            if [ -f "$iter_dir/results.txt" ]; then
                echo "  FIO Results:"
                cat "$iter_dir/results.txt" | sed 's/^/    /'
                echo ""
            fi
            
            # Analyze perf data
            analyze_perf_report "$iter_dir/perf_report.txt" "netCAS"
            
            # Analyze system metrics
            analyze_system_metrics "$iter_dir" "netCAS"
            
            echo "  ---"
        fi
    done
else
    echo "netCAS results not found"
fi

echo ""

# Analyze MF results
if [ -d "$RESULTS_DIR/MF" ]; then
    echo "=== MF Implementation Analysis ==="
    
    for iter_dir in "$RESULTS_DIR/MF"/iteration_*; do
        if [ -d "$iter_dir" ]; then
            iter_num=$(basename "$iter_dir" | sed 's/iteration_//')
            echo "Iteration $iter_num:"
            
            # Show FIO results
            if [ -f "$iter_dir/results.txt" ]; then
                echo "  FIO Results:"
                cat "$iter_dir/results.txt" | sed 's/^/    /'
                echo ""
            fi
            
            # Analyze perf data
            analyze_perf_report "$iter_dir/perf_report.txt" "MF"
            
            # Analyze system metrics
            analyze_system_metrics "$iter_dir" "MF"
            
            echo "  ---"
        fi
    done
else
    echo "MF results not found"
fi

echo ""

# Generate comparison summary
echo "=== Key Differences Analysis ==="

# Check if comparison file exists
if [ -f "$RESULTS_DIR/comparison.txt" ]; then
    echo "Full comparison report: $RESULTS_DIR/comparison.txt"
    echo ""
fi

echo "=== Analysis Tips ==="
echo "1. Look for differences in top CPU-consuming functions between implementations"
echo "2. Compare system CPU usage patterns (mpstat)"
echo "3. Check for background thread activity in MF implementation"
echo "4. Focus on functions related to:"
echo "   - Cache management"
echo "   - Request routing"
echo "   - Performance monitoring"
echo "   - RDMA operations"
echo ""
echo "5. Key areas to investigate:"
echo "   - netCAS: Direct split ratio calculation, no background threads"
echo "   - MF: Background monitoring thread, continuous tuning"
echo ""

echo "=== Next Steps ==="
echo "1. Run detailed perf analysis: perf report -i <perf.data>"
echo "2. Check for kernel thread activity: ps aux | grep -i cas"
echo "3. Monitor real-time CPU usage: top -p <fio_pid>"
echo "4. Compare function call graphs: perf script -i <perf.data>"
