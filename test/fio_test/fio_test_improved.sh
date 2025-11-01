#!/bin/bash

# Set devices and parameters
devices=("/dev/cas1-1")
iodepths=(16)
jobnums=(1)
block_size="64k"
output_file="base.csv"
iterations=1

# Create CSV header
echo "Device,IOdepth,Jobnum,Iteration,Test_Type,IOPS" > $output_file

# Loop through devices, iodepths, and jobnums
for device in "${devices[@]}"; do
  for iodepth in "${iodepths[@]}"; do
    for jobnum in "${jobnums[@]}"; do
      for iter in $(seq 1 $iterations); do
        
        echo "=== Iteration $iter ==="
        
        # Clear dmesg to start fresh
        echo "Clearing dmesg..."
        sudo dmesg -c > /dev/null
        
        # Test 1: Cache Miss Read (Backend to Cache)
        echo "Test 1: Cache Miss Read (Backend to Cache)"
        
        # Flush cache to ensure cache miss
        echo "Flushing cache..."
        sudo casadm -F -i 1
        
        # Reset statistics
        echo "Resetting statistics..."
        sudo casadm -Z -i 1
        
        sleep 2
        
        # Run read test with cache miss
        fio_cmd="fio --name=cache_miss_read --filename=$device --rw=randread --bs=$block_size --direct=1 \
                 --ioengine=libaio --iodepth=$iodepth --size=100M --time_based --numjobs=$jobnum \
                 --runtime=30 --group_reporting --output-format=json"
        
        echo "Running cache miss read test: $fio_cmd"
        fio_output=$($fio_cmd)
        iops=$(echo $fio_output | jq '.jobs[] | .read.iops')
        echo "$device,$iodepth,$jobnum,$iter,cache_miss,$iops" >> $output_file
        
        # Show dmesg for cache miss
        echo "=== Cache Miss Read dmesg ==="
        dmesg | grep -E "(mfwa|NETCAS)" | tail -10
        
        sleep 5
        
        # Test 2: Cache Hit Read (Cache Only)
        echo "Test 2: Cache Hit Read (Cache Only)"
        
        # Clear dmesg again
        sudo dmesg -c > /dev/null
        
        # Run read test with cache hit (same data should be in cache)
        fio_cmd="fio --name=cache_hit_read --filename=$device --rw=randread --bs=$block_size --direct=1 \
                 --ioengine=libaio --iodepth=$iodepth --size=100M --time_based --numjobs=$jobnum \
                 --runtime=30 --group_reporting --output-format=json"
        
        echo "Running cache hit read test: $fio_cmd"
        fio_output=$($fio_cmd)
        iops=$(echo $fio_output | jq '.jobs[] | .read.iops')
        echo "$device,$iodepth,$jobnum,$iter,cache_hit,$iops" >> $output_file
        
        # Show dmesg for cache hit
        echo "=== Cache Hit Read dmesg ==="
        dmesg | grep -E "(mfwa|NETCAS)" | tail -10
        
        sleep 5
        
        # Test 3: Mixed Read (Some hits, some misses)
        echo "Test 3: Mixed Read (Some hits, some misses)"
        
        # Clear dmesg again
        sudo dmesg -c > /dev/null
        
        # Write some new data to create mixed scenario
        echo "Writing new data for mixed test..."
        fio --name=write_mixed --filename=$device --rw=write --bs=$block_size --direct=1 \
            --ioengine=libaio --iodepth=16 --size=200M --numjobs=1 --runtime=10 \
            --group_reporting --output-format=json > /dev/null
        
        sleep 2
        
        # Run read test with mixed scenario
        fio_cmd="fio --name=mixed_read --filename=$device --rw=randread --bs=$block_size --direct=1 \
                 --ioengine=libaio --iodepth=$iodepth --size=200M --time_based --numjobs=$jobnum \
                 --runtime=30 --group_reporting --output-format=json"
        
        echo "Running mixed read test: $fio_cmd"
        fio_output=$($fio_cmd)
        iops=$(echo $fio_output | jq '.jobs[] | .read.iops')
        echo "$device,$iodepth,$jobnum,$iter,mixed,$iops" >> $output_file
        
        # Show dmesg for mixed scenario
        echo "=== Mixed Read dmesg ==="
        dmesg | grep -E "(mfwa|NETCAS)" | tail -10
        
        echo "=== Iteration $iter completed ==="
        echo ""
        
      done
    done
  done
done

echo "FIO tests completed and results saved to $output_file"
echo ""
echo "Summary of dmesg logs:"
dmesg | grep -E "(mfwa|NETCAS)" | tail -20 