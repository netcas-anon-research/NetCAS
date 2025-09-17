#!/bin/bash

# Automated CPU Test Runner
# This script demonstrates the full automated testing workflow

set -e

echo "=== Automated CPU Test Runner ==="
echo "This script will:"
echo "1. Test netCAS implementation"
echo "2. Switch to MF implementation"
echo "3. Test MF implementation"
echo "4. Generate comparison report"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Resolve CPU profiling directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPU_PROFILING_DIR="$SCRIPT_DIR/CPU_profiling"

# Step 1: Test netCAS implementation
print_status "Step 1: Testing netCAS implementation..."
sudo "$CPU_PROFILING_DIR/simple_cpu_test.sh" --netcas-only

if [ $? -eq 0 ]; then
    print_success "netCAS test completed successfully"
else
    echo "Error: netCAS test failed"
    exit 1
fi

echo ""
print_warning "Step 2: Switching to MF implementation..."
print_status "This will rebuild and switch to the MF implementation..."

# Step 2: Switch to MF implementation
cd "$SCRIPT_DIR/../shell"
sudo ./rebuild_selector.sh 3
cd "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    print_success "Successfully switched to MF implementation"
else
    echo "Error: Failed to switch to MF implementation"
    exit 1
fi

# Wait for the system to stabilize
print_status "Waiting 15 seconds for system to stabilize..."
sleep 15

# Step 3: Test MF implementation
print_status "Step 3: Testing MF implementation..."
sudo "$CPU_PROFILING_DIR/simple_cpu_test.sh" --mf-only

if [ $? -eq 0 ]; then
    print_success "MF test completed successfully"
else
    echo "Error: MF test failed"
    exit 1
fi

# Step 4: Generate comparison report
print_status "Step 4: Generating comparison report..."
"$CPU_PROFILING_DIR/analyze_results.sh"

print_success "=== Automated Test Complete ==="
echo ""
echo "Results are available in: $CPU_PROFILING_DIR/cpu_test_results/"
echo "Comparison report: $CPU_PROFILING_DIR/cpu_test_results/comparison.txt"
echo ""
echo "To analyze results in detail, run: $CPU_PROFILING_DIR/analyze_results.sh"
