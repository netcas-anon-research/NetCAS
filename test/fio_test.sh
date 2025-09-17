#!/bin/bash

# Set devices and parameters
devices=("/dev/cas1-1")
iodepths=(16)
jobnums=(1)
# 1 2 4 8 16 32 64
block_size="64k"
output_file="base_16.csv"
iterations=1

# Create CSV header
echo "Device,IOdepth,Jobnum,Iteration,IOPS" > $output_file

# Loop through devices, iodepths, and jobnums
for device in "${devices[@]}"; do
  for iodepth in "${iodepths[@]}"; do
    for jobnum in "${jobnums[@]}"; do
      for iter in $(seq 1 $iterations); do
        # First, do a warmup write pass to populate the cache
        # Sequential write로 캐시 채우기
        warmup_seq_cmd="fio --name=warmup_seq --filename=$device --rw=write --bs=$block_size --direct=1 \
                           --ioengine=libaio --iodepth=32 --size=1G --numjobs=1 \
                           --group_reporting --output-format=json"
        
        echo "Sequential warmup: $warmup_seq_cmd"
        $warmup_seq_cmd
        
        # Random write로 캐시 완전히 채우기
        warmup_cmd="fio --name=warmup --filename=$device --rw=randwrite --bs=$block_size --direct=1 \
                       --ioengine=libaio --iodepth=32 --size=1G --numjobs=1 --runtime=120 \
                       --group_reporting --output-format=json"
        
        echo "Random warmup: $warmup_cmd"
        $warmup_cmd

        # Sleep briefly to ensure all writes are completed
        sleep 5

        flushing_cmd="sudo casadm -F -i 1"
        echo "Flushing cache: $flushing_cmd"
        $flushing_cmd

        dmesg_flushing_cmd="sudo dmesg -c"
        echo "Dmesg Flusing: $dmesg_flushing_cmd"
        $dmesg_flushing_cmd

        # Reset statistics using casadm -Z
        reset_stats_cmd="sudo casadm -Z -i 1"
        echo "Resetting statistics: $reset_stats_cmd"
        $reset_stats_cmd

        # Sleep briefly to ensure all writes are completed
        sleep 5

        # Now do the actual read test - it will hit cache since we just wrote this data
        # *** 같은 크기(1G)로 읽기 테스트 - 캐시 히트 100% 보장 ***
        fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
                 --ioengine=libaio --iodepth=$iodepth --size=1G --time_based --numjobs=$jobnum \
                 --runtime=100 --group_reporting --output-format=json"

        # fio_cmd="fio --name=test --filename=$device --rw=randread --bs=$block_size --direct=1 \
        #      --ioengine=libaio --iodepth=$iodepth --size=1G --time_based --numjobs=$jobnum \
        #      --runtime=60 --group_reporting --output-format=json \
        #      --write_bw_log=throughput_log --bw-log-interval=1000"

        # Print fio command for debugging
        echo "Running command: $fio_cmd"

        # Run fio test
        fio_output=$($fio_cmd)
        
        # Parse IOPS from fio output using jq
        iops=$(echo $fio_output | jq '.jobs[] | .read.iops')
        
        # Append results to CSV file
        echo "$device,$iodepth,$jobnum,$iter,$iops" >> $output_file
      done
    done
  done
done

echo "FIO tests completed and results saved to $output_file"
