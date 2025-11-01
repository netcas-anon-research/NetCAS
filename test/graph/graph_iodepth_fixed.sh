#!/bin/bash

# Set devices and parameters
devices=("/dev/cas1-1")
iodepths=(16)
jobnums=(1)
block_size="64k"
output_dir="iodepth_logs_cas1-1_test4"
sample_interval=1

# Create output directory
mkdir -p $output_dir

# Function to save netCAS logs to sample.txt
save_netcas_log() {
  local output_dir="$1"
  local log_file="$output_dir/sample.txt"
  echo "Saving netCAS logs to $log_file"
  dmesg -T | grep "netCAS" > "$log_file"
  
  # Check if netCAS logs exist
  if [[ ! -s "$log_file" ]]; then
    echo "Warning: No netCAS logs found in dmesg"
    echo "Checking for alternative log patterns..."
    dmesg -T | grep -i "optimal_split_ratio\|average_rdma_throughput" > "$log_file"
  fi
}

# Function to generate netCAS graphs
generate_netcas_graphs() {
  local output_dir="$1"
  local log_file="$output_dir/sample.txt"
  local data_file="$output_dir/netcas_data.dat"
  
  # Check if log file exists and has content
  if [[ ! -s "$log_file" ]]; then
    echo "Warning: $log_file is empty or does not exist. Skipping netCAS graphs."
    return
  fi

  local plot_script_combined="$output_dir/netcas_plot.gp"
  local plot_png_combined="$output_dir/netcas_plot.png"
  local plot_script_ratio="$output_dir/netcas_ratio_plot.gp"
  local plot_png_ratio="$output_dir/netcas_ratio_plot.png"
  local plot_script_throughput="$output_dir/netcas_throughput_plot.gp"
  local plot_png_throughput="$output_dir/netcas_throughput_plot.png"

  # Extract time, optimal_split_ratio, average_rdma_throughput
  echo "Extracting netCAS data from $log_file"
  grep "optimal_split_ratio" "$log_file" | \
    sed -n 's/.*optimal_split_ratio=\([0-9]*\), average_rdma_throughput=\([0-9]*\).*/\1 \2/p' | \
    awk '{print NR, $1, $2}' > "$data_file"
  
  # Check if data was extracted
  if [[ ! -s "$data_file" ]]; then
    echo "Warning: No data extracted from netCAS logs. Check log format."
    return
  fi

  echo "Extracted $(wc -l < "$data_file") data points"

  # Combined graph
  cat > "$plot_script_combined" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$plot_png_combined'
set title 'netCAS: optimal_split_ratio, average_rdma_throughput'
set xlabel 'Time (seconds)'
set ylabel 'optimal_split_ratio'
set y2label 'average_rdma_throughput'
set ytics nomirror
set y2tics
set grid
plot \
  '$data_file' using 1:2 with lines title 'optimal_split_ratio' axis x1y1, \
  '$data_file' using 1:3 with lines title 'average_rdma_throughput' axis x1y2
EOL

  # optimal_split_ratio only
  cat > "$plot_script_ratio" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$plot_png_ratio'
set title 'netCAS: optimal_split_ratio over time'
set xlabel 'Time (seconds)'
set ylabel 'optimal_split_ratio'
set grid
plot '$data_file' using 1:2 with lines title 'optimal_split_ratio'
EOL

  # average_rdma_throughput only
  cat > "$plot_script_throughput" << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$plot_png_throughput'
set title 'netCAS: average_rdma_throughput over time'
set xlabel 'Time (seconds)'
set ylabel 'average_rdma_throughput'
set grid
plot '$data_file' using 1:3 with lines title 'average_rdma_throughput'
EOL

  # Run gnuplot
  echo "Generating netCAS graphs"
  gnuplot "$plot_script_combined" 2>&1 || echo "Error generating combined graph"
  gnuplot "$plot_script_ratio" 2>&1 || echo "Error generating ratio graph"
  gnuplot "$plot_script_throughput" 2>&1 || echo "Error generating throughput graph"
  echo "netCAS graphs generated"
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

      # Now run the actual test with IO depth monitoring
      echo "Starting IO depth monitoring test for $test_id"
      
      # Set up FIO with detailed logging - FIXED the log parameter
      fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
               --ioengine=libaio --iodepth=$iodepth --size=1G --time_based --numjobs=$jobnum \
               --runtime=60 --group_reporting --output-format=json \
               --write_bw_log=$output_dir/${test_id} \
               --log_avg_msec=100 \
               --status-interval=$sample_interval"
      
      # Print fio command for debugging
      echo "Running command: $fio_cmd"
      
      # Run the FIO test and save output
      $fio_cmd | tee $log_file
      
      # Check if bandwidth log file exists
      bw_log_file="$output_dir/${test_id}_bw.1.log"
      if [[ ! -f "$bw_log_file" ]]; then
        echo "Error: Bandwidth log file $bw_log_file not found"
        continue
      fi
      
      echo "Bandwidth log file size: $(wc -l < "$bw_log_file") lines"
      echo "Sample data:"
      head -3 "$bw_log_file"
      
      # Generate graph using gnuplot - FIXED the syntax error
      gnuplot_script="$output_dir/${test_id}_plot.gp"
      cat > $gnuplot_script << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$output_dir/${test_id}_iodepth.png'
set title 'IOPS over time - $test_id'
set xlabel 'Time (milliseconds)'
set ylabel 'IOPS (for 64k block size)'
set format y "%.0f"
set grid
plot '$bw_log_file' using 1:(\$2/64) with lines title 'IOPS (64k)'
EOL
      
      # Run gnuplot with error handling
      echo "Generating graph for $test_id"
      if gnuplot $gnuplot_script 2>&1; then
        echo "Graph generated successfully: $output_dir/${test_id}_iodepth.png"
      else
        echo "Error generating graph with gnuplot"
      fi
      
      # Check if PNG was created and has content
      png_file="$output_dir/${test_id}_iodepth.png"
      if [[ -s "$png_file" ]]; then
        echo "PNG file created successfully: $(ls -lh "$png_file" | awk '{print $5}')"
      else
        echo "Error: PNG file is empty or not created"
      fi
      
      # Save netCAS log and generate netCAS graphs
      save_netcas_log "$output_dir"
      generate_netcas_graphs "$output_dir"
      
      echo "Test completed for $test_id"
      echo "Results saved to $output_dir/${test_id}_iodepth.png"
      echo "-------------------------------------------------"
    done
  done
done

echo "All tests completed. Check $output_dir/ for results."