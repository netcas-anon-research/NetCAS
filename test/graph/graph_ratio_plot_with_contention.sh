#!/bin/bash

# Set devices and parameters
devices=("/dev/cas1-1")
iodepths=(16)
jobnums=(1)
block_size="64k"
output_dir="graph_logs_cas-NETCAS_with_contention_mf"
sample_interval=1

# Create output directory
mkdir -p $output_dir

# Function to save monitor logs to sample.txt
save_monitor_log() {
  local output_dir="$1"
  local log_file="$output_dir/sample.txt"
  echo "Saving monitor logs to $log_file"
  dmesg -T | grep "MONITOR: query_load_admit returning" > "$log_file"
}

# Function to get contention start time from white server
get_contention_start_time() {
  local test_start_time=$(date +%s)
  echo "Test started at timestamp: $test_start_time"
  
  # Run the contention script and capture its output
  echo "Running contention script to get start time..."
  local contention_output=$(./white_contention.sh 2>&1)
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

# Function to generate ratio graphs with server-side contention timing
generate_ratio_graphs() {
  local output_dir="$1"
  local log_file="$output_dir/sample.txt"
  local data_file="$output_dir/ratio_data.dat"
  local plot_script="$output_dir/ratio_plot.gp"
  local plot_png="$output_dir/ratio_plot.png"
  local contention_start_time="$2"  # Server-side contention start time

  # Extract ratio values from monitor logs using simple approach
  # Format: [timestamp] MONITOR: query_load_admit returning: [value]
  echo "Processing log file: $log_file"
  
  grep "MONITOR: query_load_admit returning" "$log_file" | \
    sed -n 's/.*returning: \([0-9]*\)/\1/p' | \
    awk 'BEGIN {count=0} 
         {
           count++
           print count, $1
         }' > "$data_file"

  # Check if data file has content
  if [ ! -s "$data_file" ]; then
    echo "Error: No data extracted from log file"
    echo "Log file content (first 5 lines):"
    head -5 "$log_file"
    return 1
  fi

  echo "Data file created with $(wc -l < "$data_file") lines"
  
  # Show value distribution
  echo "Value distribution:"
  cut -d' ' -f2 "$data_file" | sort | uniq -c | sort -n

  # Generate ratio plot with server-side contention timing
  cat > "$plot_script" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$plot_png'
set title 'Load Admit Ratio over Time (Sample Points) - With Server-Side Contention Timing'
set xlabel 'Sample Number'
set ylabel 'Load Admit Ratio'
set grid
set key top left
set yrange [0:10000]
set ytics 1000

# Add vertical lines to mark contention intervals with server-side timing
set arrow from $contention_start_time,0 to $contention_start_time,10000 nohead lc rgb "red" lw 2
set arrow from 30,0 to 30,10000 nohead lc rgb "red" lw 2

# Add labels for contention intervals
set label "Contention\nStarts\n(Server)" at $contention_start_time,8000 center rotate by 90 textcolor rgb "red"
set label "Contention\nEnds" at 30,8000 center rotate by 90 textcolor rgb "red"

plot '$data_file' using 1:2 with lines title 'Load Admit Ratio' linewidth 1
EOL

  # Run gnuplot
  echo "Generating ratio graph with dynamic contention timing"
  gnuplot "$plot_script"
  if [ $? -eq 0 ]; then
    echo "Ratio graph saved to $plot_png"
    echo "File size: $(ls -lh $plot_png | awk '{print $5}')"
  else
    echo "Error: Failed to generate graph"
  fi
}

# Function to generate FIO performance graphs (bandwidth and latency) with server-side timing
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

plot '$output_dir/${test_id}_bw.1.log' using 1:2 with lines title 'Bandwidth (MB/s)'
EOL

  # Generate latency graph using gnuplot
  local lat_plot_script="$output_dir/${test_id}_lat_plot.gp"
  local lat_plot_png="$output_dir/${test_id}_latency.png"
  
  cat > "$lat_plot_script" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$lat_plot_png'
set title 'Latency over time - $test_id (With Server-Side Contention Timing)'
set xlabel 'Time (milliseconds)'
set ylabel 'Latency (microseconds)'
set format y "%.0f"
set grid

# Add vertical lines to mark contention intervals with server-side timing
set arrow from $contention_start_ms,0 to $contention_start_ms,10000 nohead lc rgb "red" lw 2
set arrow from 30000,0 to 30000,10000 nohead lc rgb "red" lw 2

# Add labels for contention intervals
set label "Contention\nStarts\n(Server)" at $contention_start_ms,8000 center rotate by 90 textcolor rgb "red"
set label "Contention\nEnds" at 30000,8000 center rotate by 90 textcolor rgb "red"

plot '$output_dir/${test_id}_lat.1.log' using 1:2 with lines title 'Latency (us)'
EOL

  # Run gnuplot for both graphs
  echo "Generating FIO performance graphs with dynamic contention timing"
  gnuplot "$bw_plot_script"
  if [ $? -eq 0 ]; then
    echo "Bandwidth graph saved to $bw_plot_png"
  else
    echo "Error: Failed to generate bandwidth graph"
  fi
  
  gnuplot "$lat_plot_script"
  if [ $? -eq 0 ]; then
    echo "Latency graph saved to $lat_plot_png"
  else
    echo "Error: Failed to generate latency graph"
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

# Loop through devices, iodepths, and jobnums
for device in "${devices[@]}"; do
  for iodepth in "${iodepths[@]}"; do
    for jobnum in "${jobnums[@]}"; do
      # Create unique test identifier
      test_id="${device//\//_}_iodepth${iodepth}_jobs${jobnum}"
      log_file="$output_dir/${test_id}.log"
      
      # First, do a warmup write pass to populate the cache
      warmup_cmd="fio --name=warmup --filename=$device --rw=write --bs=$block_size --direct=1 \
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
      
      # Set up FIO with detailed logging (bandwidth and latency)
      fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
               --ioengine=libaio --iodepth=$iodepth --size=1G --time_based --numjobs=$jobnum \
               --runtime=60 --group_reporting --output-format=json \
               --write_bw_log=$output_dir/${test_id} \
               --write_lat_log=$output_dir/${test_id} \
               --log_avg_msec=100 \
               --status-interval=$sample_interval"
      
      # Print fio command for debugging
      echo "Running command: $fio_cmd"
      
      # Start FIO in background
      $fio_cmd > $log_file 2>&1 &
      fio_pid=$!
      echo "FIO started with PID: $fio_pid"
      
      # Wait 10 seconds (no contention period)
      echo "Phase 1: No contention (0-10 seconds)"
      sleep 10
      
      # Start network contention and get actual start time
      echo "Phase 2: Starting contention (10-30 seconds)"
      echo "Getting contention start time from white server..."
      
      # Get the actual start time from the white server
      get_contention_start_time
      contention_start_time=$?
      echo "Contention will start at: ${contention_start_time} seconds"
      
      # Calculate remaining time for contention to run
      contention_duration=$((30 - contention_start_time))
      echo "Contention will run for ${contention_duration} seconds"
      sleep $contention_duration
      
      # Phase 3: Contention ends, returning to no contention (30-60 seconds)
      echo "Phase 3: Contention ended, returning to no contention (30-60 seconds)"
      
      # Wait for FIO to complete
      echo "Waiting for FIO to complete..."
      wait $fio_pid
      echo "FIO completed"
      
      # Save monitor log and generate ratio graphs
      save_monitor_log "$output_dir"
      generate_ratio_graphs "$output_dir" "$contention_start_time"
      
      # Generate FIO performance graphs (bandwidth and latency)
      generate_fio_graphs "$output_dir" "$test_id" "$contention_start_time"
      
      echo "Test completed for $test_id"
      echo "Results saved to:"
      echo "  - $output_dir/ratio_plot.png (Load Admit Ratio with server-side contention timing)"
      echo "  - $output_dir/${test_id}_bandwidth.png (Bandwidth with server-side contention timing)"
      echo "  - $output_dir/${test_id}_latency.png (Latency with server-side contention timing)"
      echo "-------------------------------------------------"
    done
  done
done
