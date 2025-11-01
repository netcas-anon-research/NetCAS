#!/bin/bash

# Set devices and parameters
# devices=("/dev/nvme2n1")
devices=("/dev/cas1-1")
iodepths=(16)
jobnums=(1)
block_size="64k"
output_dir="iodepth_logs_cas1-1_test3"
sample_interval=1  # Increased from 0.5 to 1 second

# Create output directory
mkdir -p $output_dir

# Function to save netCAS logs to sample.txt
save_netcas_log() {
  local output_dir="$1"
  local log_file="$output_dir/sample.txt"
  echo "Saving netCAS logs to $log_file"
  dmesg -T | grep "netCAS" > "$log_file"
}

# Function to generate netCAS graphs
# 1. Combined graph
# 2. optimal_split_ratio only
# 3. average_rdma_throughput only
generate_netcas_graphs() {
  local output_dir="$1"
  local log_file="$output_dir/sample.txt"
  local data_file="$output_dir/netcas_data.dat"
  local plot_script_combined="$output_dir/netcas_plot.gp"
  local plot_png_combined="$output_dir/netcas_plot.png"
  local plot_script_ratio="$output_dir/netcas_ratio_plot.gp"
  local plot_png_ratio="$output_dir/netcas_ratio_plot.png"
  local plot_script_throughput="$output_dir/netcas_throughput_plot.gp"
  local plot_png_throughput="$output_dir/netcas_throughput_plot.png"

  # Extract time, optimal_split_ratio, average_rdma_throughput, and difference
  grep "optimal_split_ratio" "$log_file" | \
    sed -n 's/.*optimal_split_ratio=\([0-9]*\), average_rdma_throughput=\([0-9]*\), difference=\([0-9]*\).*/\1 \2 \3/p' | \
    awk '{print NR, $1, $2, $3}' > "$data_file"

  # Combined graph (now with difference as a third y2 axis)
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

#   # difference only
#   local plot_script_difference="$output_dir/netcas_difference_plot.gp"
#   local plot_png_difference="$output_dir/netcas_difference_plot.png"
#   cat > "$plot_script_difference" << EOL
# set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
# set output '$plot_png_difference'
# set title 'netCAS: difference over time'
# set xlabel 'Time (seconds)'
# set ylabel 'difference'
# set grid
# plot '$data_file' using 1:4 with lines title 'difference'
# EOL

  # Run gnuplot for all four
  echo "Generating netCAS graphs"
  gnuplot "$plot_script_combined"
  gnuplot "$plot_script_ratio"
  gnuplot "$plot_script_throughput"
  # gnuplot "$plot_script_difference"
  echo "netCAS graphs saved to $plot_png_combined, $plot_png_ratio, $plot_png_throughput"
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
      sleep 5

      # echo "Starting white contention"
      # sudo ./white_contention.sh
      # sleep 5

      # Now run the actual test with IO depth monitoring
      echo "Starting IO depth monitoring test for $test_id"
      
      # Set up FIO with detailed logging - fixed logging parameters
      fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
               --ioengine=libaio --iodepth=$iodepth --size=1G --time_based --numjobs=$jobnum \
               --runtime=60 --group_reporting --output-format=json \
               --write_bw_log=$output_dir/${test_id} \
               --log_avg_msec=100 \
               --status-interval=$sample_interval
               "
      
      # Print fio command for debugging
      echo "Running command: $fio_cmd"
      
      # Run the FIO test and save output
      $fio_cmd | tee $log_file
      
      # Generate graph using gnuplot - updated to use the correct log file format
      gnuplot_script="$output_dir/${test_id}_plot.gp"
      cat > $gnuplot_script << EOL
set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output '$output_dir/${test_id}_iodepth.png'
set title 'IOPS over time - $test_id'
set xlabel 'Time (milliseconds)'
set ylabel 'IOPS (for 64k block size)'
set format y "%.0f"
set grid
plot '$output_dir/${test_id}_bw.1.log' using 1:($2/64) with lines title 'IOPS (64k)'

EOL
      
      # Run gnuplot
      echo "Generating graph for $test_id"
      gnuplot $gnuplot_script
      
      # Save netCAS log and generate netCAS graphs
      save_netcas_log "$output_dir"
      generate_netcas_graphs "$output_dir"
      
      echo "Test completed for $test_id"
      echo "Results saved to $output_dir/${test_id}_iodepth.png"
      echo "-------------------------------------------------"
    done
  done
done