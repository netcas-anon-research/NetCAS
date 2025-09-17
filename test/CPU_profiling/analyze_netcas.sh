#!/bin/bash

# netCAS CPU Usage Analysis Script
# This script analyzes CPU usage by different categories for netCAS system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}netCAS CPU Usage Analysis Tool${NC}"
echo "=================================="

# Resolve script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not installed.${NC}"
    exit 1
fi

# Check if required packages are installed
echo -e "${YELLOW}Checking Python dependencies...${NC}"
python3 -c "import matplotlib, pandas, numpy" 2>/dev/null || {
    echo -e "${YELLOW}Installing required Python packages...${NC}"
    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        pip3 install -r "$SCRIPT_DIR/requirements.txt"
    else
        # Fallback to installing known deps
        pip3 install matplotlib pandas numpy
    fi
}

# Default values
TEST_DIR=""
OUTPUT_DIR=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 TEST_DIR [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  TEST_DIR             Directory containing perf_report.txt, mpstat.log, vmstat.log, and results.txt"
            echo ""
            echo "Options:"
            echo "  --output-dir DIR     Output directory (default: <TEST_DIR>_analysis)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 test/cpu_test_results/netCAS/iteration_2"
            echo "  $0 test/cpu_test_results/netCAS/iteration_2 --output-dir my_analysis"
            exit 0
            ;;
        *)
            if [[ -z "$TEST_DIR" ]]; then
                TEST_DIR="$1"
            else
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if test directory is provided
if [[ -z "$TEST_DIR" ]]; then
    echo -e "${RED}Error: TEST_DIR is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

# Check if test directory exists
if [[ ! -d "$TEST_DIR" ]]; then
    echo -e "${RED}Error: Test directory '$TEST_DIR' not found${NC}"
    exit 1
fi

# Determine default output dir if not specified
DEFAULT_OUT="$TEST_DIR/analysis_python"

# Build command using script-relative analyzer
CMD="python3 \"$SCRIPT_DIR/analyze_netcas_cpu.py\" '$TEST_DIR'"

if [[ -n "$OUTPUT_DIR" ]]; then
    CMD="$CMD --output-dir '$OUTPUT_DIR'"
else
    CMD="$CMD --output-dir '$DEFAULT_OUT'"
fi

echo -e "${GREEN}Running CPU analysis...${NC}"
echo "Command: $CMD"
echo ""

# Run the analysis
eval $CMD

echo ""
echo -e "${GREEN}Analysis complete!${NC}"
echo -e "Check the '$OUTPUT_DIR' directory for detailed reports and visualizations."

