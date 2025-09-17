#!/bin/bash

set -e  # Exit on any error

echo "Open CAS Linux Rebuild Selector"
echo "================================"
echo ""

# Define the available open-cas-linux directories
OPEN_CAS_DIRS=(
    "open-cas-linux"
    "open-cas-linux-netCAS"
    "open-cas-linux-mf"
    "open-cas-linux-ours"
)

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if directory exists and has Makefile
check_directory() {
    local dir="$1"
    # Check if we're in shell directory, if so, look in parent directory
    if [ -d "../$dir" ]; then
        echo "✅ Directory '../$dir' is valid"
        return 0
    elif [ -d "$dir" ]; then
        # Already in correct location
        if [ ! -f "$dir/Makefile" ]; then
            echo "❌ Directory '$dir' does not contain a Makefile"
            return 1
        fi
        echo "✅ Directory '$dir' is valid"
        return 0
    else
        echo "❌ Directory '$dir' does not exist"
        return 1
    fi
}

# Function to rebuild a specific open-cas-linux directory
rebuild_directory() {
    local target_dir="$1"
    
    echo ""
    echo "Starting rebuild for: $target_dir"
    echo "================================"
    
    # Determine the correct path to the target directory
    local actual_path="$target_dir"
    if [ -d "../$target_dir" ]; then
        # We're in shell directory, but after teardown we'll be in parent directory
        actual_path="$target_dir"  # Use relative path from parent directory
    elif [ -d "$target_dir" ]; then
        actual_path="$target_dir"
    else
        echo "Error: Directory '$target_dir' not found. Please run this script from the netCAS root directory or shell directory."
        exit 1
    fi
    
    # Determine shell directory path
    local shell_path="shell"
    if [ -d "../shell" ]; then
        shell_path="../shell"
    fi
    
    # Check if required commands exist
    if ! command_exists make; then
        echo "Error: make command not found"
        exit 1
    fi
    
    if ! command_exists insmod; then
        echo "Error: insmod command not found"
        exit 1
    fi
    
    # Teardown existing setup
    echo "Tearing down existing Open CAS setup..."
    cd "$shell_path"
    if [ -f "teardown_opencas_pmem.sh" ]; then
        # Teardown script now auto-detects the running variant
        sudo ./teardown_opencas_pmem.sh || echo "Warning: Teardown had issues, continuing..."
    else
        echo "Warning: teardown_opencas_pmem.sh not found, skipping teardown"
    fi
    cd ..
    
    # Remove existing modules
    echo "Removing existing kernel modules..."
    sudo rmmod cas_cache 2>/dev/null || echo "cas_cache module not loaded"
    sudo rmmod cas_disk 2>/dev/null || echo "cas_disk module not loaded"
    

    
    # Change to target directory
    cd "$actual_path"
    
    # Verify Makefile exists
    if [ ! -f "Makefile" ]; then
        echo "Error: Makefile not found in '$actual_path'. Please ensure this is a valid open-cas-linux directory."
        exit 1
    fi
    
    # Clean previous build
    echo "Cleaning previous build..."
    sudo make clean
    
    # Build with DEBUG=1
    echo "Building with DEBUG=1..."
    sudo make DEBUG=1 -j $(nproc)
    
    # Install
    echo "Installing with DEBUG=1..."
    sudo make install DEBUG=1 -j $(nproc)
    
    # Check if modules are already loaded and unload them if necessary
    echo "Checking for already loaded modules..."
    if lsmod | grep -q "cas_cache"; then
        echo "Unloading existing cas_cache module..."
        sudo rmmod cas_cache 2>/dev/null || echo "Warning: Could not unload cas_cache"
    fi
    if lsmod | grep -q "cas_disk"; then
        echo "Unloading existing cas_disk module..."
        sudo rmmod cas_disk 2>/dev/null || echo "Warning: Could not unload cas_disk"
    fi
    
    # Load modules using insmod to ensure we load the newly built modules
    echo "Loading kernel modules..."
    echo "Loading cas_disk module..."
    sudo insmod modules/cas_disk/cas_disk.ko
    echo "Loading cas_cache module..."
    sudo insmod modules/cas_cache/cas_cache.ko
    
    # Verify modules are loaded with correct version using sysfs
    echo "Verifying module versions..."
    if [ -f "/sys/module/cas_disk/version" ]; then
        local disk_version=$(sudo cat /sys/module/cas_disk/version)
        local disk_srcversion=$(sudo cat /sys/module/cas_disk/srcversion)
        echo "✅ cas_disk version: $disk_version"
        echo "✅ cas_disk srcversion: $disk_srcversion"
    else
        echo "❌ cas_disk module not loaded properly"
        exit 1
    fi
    
    if [ -f "/sys/module/cas_cache/version" ]; then
        local cache_version=$(sudo cat /sys/module/cas_cache/version)
        local cache_srcversion=$(sudo cat /sys/module/cas_cache/srcversion)
        echo "✅ cas_cache version: $cache_version"
        echo "✅ cas_cache srcversion: $cache_srcversion"
    else
        echo "❌ cas_cache module not loaded properly"
        exit 1
    fi
    
    echo "Build process completed successfully!"
    
    # Setup Open CAS
    echo "Setting up Open CAS..."
    # Go back to shell directory
    if [ -d "../shell" ]; then
        cd ../shell
    else
        cd "$shell_path"
    fi
    
    # Connect RDMA if script exists
    if [ -f "connect-rdma.sh" ]; then
        sudo ./connect-rdma.sh || echo "Warning: RDMA connection had issues"
    else
        echo "Warning: connect-rdma.sh not found, skipping RDMA setup"
    fi
    
    # Setup Open CAS PMEM if script exists
    if [ -f "setup_opencas_pmem.sh" ]; then
        # Pass variant parameter to setup script based on target directory
        local variant_param=""
        if [[ "$target_dir" == *"mf"* ]]; then
            variant_param="mf"
            echo "Detected MF variant - will perform multi-factor monitor setup"
        fi
        
        if [ -n "$variant_param" ]; then
            sudo ./setup_opencas_pmem.sh "$variant_param" || echo "Warning: Open CAS PMEM setup had issues"
        else
            sudo ./setup_opencas_pmem.sh || echo "Warning: Open CAS PMEM setup had issues"
        fi
    else
        echo "Warning: setup_opencas_pmem.sh not found, skipping Open CAS setup"
    fi
    
    echo "Rebuild process completed for $target_dir!"
}

# Check all directories first
echo "Checking available open-cas-linux directories..."
echo ""

valid_dirs=()
for dir in "${OPEN_CAS_DIRS[@]}"; do
    if check_directory "$dir"; then
        valid_dirs+=("$dir")
    fi
done

echo ""
if [ ${#valid_dirs[@]} -eq 0 ]; then
    echo "❌ No valid open-cas-linux directories found!"
    exit 1
fi

# Check if command line argument was provided
if [ $# -gt 0 ]; then
    choice="$1"
    echo "Command line argument provided: $choice"
    
    # Check if input is a number
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid argument: '$choice' is not a number."
        exit 1
    fi
    
    # Check if choice is 0 (exit)
    if [ "$choice" -eq 0 ]; then
        echo "Exiting..."
        exit 0
    fi
    
    # Check if choice is within valid range
    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#valid_dirs[@]} ]; then
        selected_dir="${valid_dirs[$((choice-1))]}"
        echo ""
        echo "Selected: $selected_dir"
        echo ""
        
        # Automatically proceed without confirmation for command line usage
        echo "Proceeding with rebuild (automated mode)..."
        rebuild_directory "$selected_dir"
        exit 0
    else
        echo "❌ Invalid choice: $choice is not between 1 and ${#valid_dirs[@]}."
        exit 1
    fi
fi

# Display menu (interactive mode)
echo "Available directories to rebuild:"
echo ""

for i in "${!valid_dirs[@]}"; do
    echo "$((i+1)). ${valid_dirs[i]}"
done

echo ""
echo "0. Exit"
echo ""
echo "Usage: $0 [choice_number]  # For automated operation"
echo ""

# Get user input
while true; do
    read -p "Please select a directory to rebuild (0-${#valid_dirs[@]}): " choice
    
    # Check if input is a number
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        echo "❌ Please enter a valid number."
        continue
    fi
    
    # Check if choice is 0 (exit)
    if [ "$choice" -eq 0 ]; then
        echo "Exiting..."
        exit 0
    fi
    
    # Check if choice is within valid range
    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#valid_dirs[@]} ]; then
        selected_dir="${valid_dirs[$((choice-1))]}"
        echo ""
        echo "Selected: $selected_dir"
        echo ""
        
        # Confirm selection
        read -p "Proceed with rebuilding $selected_dir? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rebuild_directory "$selected_dir"
            break
        else
            echo "Rebuild cancelled."
            exit 0
        fi
    else
        echo "❌ Please enter a number between 0 and ${#valid_dirs[@]}."
    fi
done 