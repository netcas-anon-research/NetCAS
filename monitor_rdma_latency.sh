#!/bin/bash

# RDMA Latency Monitor Script
# Monitors /sys/kernel/rdma_metrics/latency every 0.1 seconds
# Logs timestamp and latency values to help diagnose overflow issues

LOG_FILE="/home/chanseo/netCAS/rdma_latency_log.txt"
LATENCY_FILE="/sys/kernel/rdma_metrics/latency"

echo "RDMA Latency Monitor Started"
echo "Logging to: $LOG_FILE"
echo "Monitoring file: $LATENCY_FILE"
echo "Press Ctrl+C to stop"
echo ""

# Check if latency file exists
if [ ! -f "$LATENCY_FILE" ]; then
    echo "ERROR: Latency file $LATENCY_FILE does not exist!"
    echo "Make sure the RDMA metrics system is running."
    exit 1
fi

# Create log file header
echo "Timestamp,Latency_Value,Hex_Value,File_Size_Bytes" > "$LOG_FILE"

echo "Starting monitoring loop..."
echo "Timestamp                | Latency Value        | Hex Value              | File Size"
echo "-------------------------|----------------------|------------------------|----------"

# Monitor loop - runs every 0.1 seconds
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    
    # Read latency value
    LATENCY_VALUE=$(cat "$LATENCY_FILE" 2>/dev/null)
    LATENCY_VALUE=${LATENCY_VALUE//[[:space:]]/}  # Remove whitespace
    
    # Convert to hex for debugging
    if [[ "$LATENCY_VALUE" =~ ^[0-9]+$ ]]; then
        HEX_VALUE=$(printf "0x%016X" "$LATENCY_VALUE" 2>/dev/null)
    else
        HEX_VALUE="INVALID"
    fi
    
    # Get file size
    FILE_SIZE=$(stat -c%s "$LATENCY_FILE" 2>/dev/null || echo "0")
    
    # Display on console
    printf "%-24s | %-20s | %-22s | %s\n" "$TIMESTAMP" "$LATENCY_VALUE" "$HEX_VALUE" "$FILE_SIZE"
    
    # Log to file
    echo "$TIMESTAMP,$LATENCY_VALUE,$HEX_VALUE,$FILE_SIZE" >> "$LOG_FILE"
    
    # Sleep for 0.1 seconds
    sleep 0.1
done
