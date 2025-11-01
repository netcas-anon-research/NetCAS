#!/bin/bash

USER=chanseo
PASS=cs1211

# Number of concurrent congestion makers per server (default: 4)
PER_SERVER=${1:-4}

# Create a temporary file to store the start time
TIMESTAMP_FILE="/tmp/contention_start_time.txt"

# 1. target 서버에서 서버 모드 실행 (백그라운드, 60초 후 자동 종료)
echo "Starting servers on targets (10.0.0.4 and 10.0.0.3) with $PER_SERVER per server..."

# Build port lists
EVEN_PORTS=""
for ((i=0;i<PER_SERVER;i++)); do
  p=$((9000 + 2*i))
  EVEN_PORTS="$EVEN_PORTS $p"
done
ODD_PORTS=""
for ((i=0;i<PER_SERVER;i++)); do
  p=$((9001 + 2*i))
  ODD_PORTS="$ODD_PORTS $p"
done

# Clean up any previous servers (best effort)
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.4 "pkill -f 'ib_write_bw -d mlx5_0' || true" >/dev/null 2>&1
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.3 "pkill -f 'ib_write_bw -d rocep2s0' || true" >/dev/null 2>&1

# Start servers on 10.0.0.4 (mlx5_0)
for PORT in $EVEN_PORTS; do
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.4 \
  "nohup timeout 120 ib_write_bw -d mlx5_0 -F -q 1 -s 1048576 --run_infinitely --report_gbits -p $PORT \
    > /tmp/ib_server_${PORT}.log 2>&1 &" >/dev/null 2>&1
done

# Start servers on 10.0.0.3 (rocep2s0)
for PORT in $ODD_PORTS; do
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.3 \
  "nohup timeout 120 ib_write_bw -d rocep2s0 -F -q 1 -s 1048576 --run_infinitely --report_gbits -p $PORT \
    > /tmp/ib_server_${PORT}.log 2>&1 &" >/dev/null 2>&1
done

# 2. 서버가 준비될 때까지 잠깐 대기
echo "Waiting for servers to be ready..."
# Check that all expected server pids exist on both hosts (retry up to ~5s)
for i in {1..10}; do
  ok4=1
  for p in $EVEN_PORTS; do
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.4 "pgrep -f \"ib_write_bw.*-p $p\" >/dev/null" || ok4=0
  done
  ok3=1
  for p in $ODD_PORTS; do
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.3 "pgrep -f \"ib_write_bw.*-p $p\" >/dev/null" || ok3=0
  done
  if [ $ok4 -eq 1 ] && [ $ok3 -eq 1 ]; then
    break
  fi
  sleep 0.5
done

# 3. white 서버에서 클라이언트 모드 실행 (20초 후 자동 종료)
echo "Starting clients on white server (10.0.0.1)..."

# Execute the command on white server and capture start time
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.1 "
# Record the start time when the command actually starts
echo \"Starting ib_write_bw at: \$(date +%s)\" > /tmp/contention_start.txt
(
  pids=()
  for p in $EVEN_PORTS; do
    ( ib_write_bw -d mlx5_1 -F -q 1 -s 1048576 -D 20 --rate_limit=2.5 --report_gbits -p \$p 10.0.0.4 ) & pids+=(\$!)
  done
  for p in $ODD_PORTS; do
    ( ib_write_bw -d mlx5_1 -F -q 1 -s 1048576 -D 20 --rate_limit=2.5 --report_gbits -p \$p 10.0.0.3 ) & pids+=(\$!)
  done
  wait \${pids[@]}
)
"



# 4. Retrieve the start time from white server
echo "Retrieving start time from white server..."
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no $USER@10.0.0.1:/tmp/contention_start.txt $TIMESTAMP_FILE

# Get the start time that was recorded
if [ -f "$TIMESTAMP_FILE" ]; then
    START_TIME=$(cat "$TIMESTAMP_FILE" | grep "Starting ib_write_bw at:" | awk '{print $4}')
    echo "Contention started at timestamp: $START_TIME"
    rm -f "$TIMESTAMP_FILE"
else
    echo "Warning: Could not retrieve start time"
fi