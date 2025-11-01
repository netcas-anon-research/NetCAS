#!/bin/bash

ENGINE_SRC="/home/chanseo/open-cas-linux/modules/cas_cache/src/ocf/engine/engine_fast.c" #Change this in other server
REBUILD_SCRIPT="/home/chanseo/open-cas-linux/rebuild.sh"
TEARDOWN_SCRIPT="/home/chanseo/netCAS/shell/teardown_opencas_pmem.sh"
CONNECT_RDMA_SCRIPT="/home/chanseo/netCAS/shell/connect-rdma.sh"
SETUP_OPENCAS_SCRIPT="/home/chanseo/netCAS/shell/setup_opencas_pmem.sh"
FIO_SCRIPT="/home/chanseo/fio_test.sh"
BASE_CSV="base.csv"
RESULT_DIR="/home/chanseo/results_best_ratio_iterations"
RATIOS=$(seq 45 -1 35)

USER=chanseo
PASS=cs1211
PORTS=(9000)

mkdir -p "$RESULT_DIR"

# # 서버 실행
# for PORT in "${PORTS[@]}"; do
#   sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.4 \
#   "nohup timeout 4000 ib_write_bw -d mlx5_0 -F -q 1 -s 1048576 --run_infinitely --report_gbits -p $PORT > /tmp/ib_server_${PORT}.log 2>&1 &"
# done

# sleep 3

# # 클라이언트 실행
# for PORT in "${PORTS[@]}"; do
#   sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@10.0.0.1 \
#   "nohup timeout 3600 ib_write_bw -d mlx5_1 -F -q 1 -s 1048576 --run_infinitely --report_gbits -p $PORT 10.0.0.4" &
# done

for ratio in $RATIOS; do
  echo "============================================"
  echo "[*] Testing with split_ratio = $ratio"

  # 1. OpenCAS 연결 해제
  echo "[1/6] Tearing down OpenCAS..."
  cd /home/chanseo/netCAS/shell
  sudo "$TEARDOWN_SCRIPT"
  cd /home/chanseo

  # 2. engine_fast.c 수정
  echo "[2/6] Modifying engine_fast.c..."
  sudo sed -i -E 's/(const[[:space:]]+uint32_t[[:space:]]+split_ratio[[:space:]]*=[[:space:]]*)[0-9]+;/\1'"${ratio}"';/' "$ENGINE_SRC"

  # 3. 재빌드
  echo "[3/6] Rebuilding..."
  cd /home/chanseo/open-cas-linux
  sudo "$REBUILD_SCRIPT" || { echo "❌ Build failed at split_ratio=$ratio"; exit 1; }
  cd /home/chanseo

  # 4. RDMA 연결
  echo "[4/6] Connecting RDMA..."
  cd /home/chanseo/netCAS/shell
  sudo "$CONNECT_RDMA_SCRIPT"

  # 5. OpenCAS 연결
  echo "[5/6] Setting up OpenCAS..."
  sudo "$SETUP_OPENCAS_SCRIPT"
  cd /home/chanseo

  # 6. FIO 실행
  echo "[6/6] Running FIO test..."
  rm -f "$BASE_CSV"
  sudo "$FIO_SCRIPT"

  # 7. dmesg 저장
  echo "[7/7] Saving dmesg..."
  dmesg > "$RESULT_DIR/dmesg_split_${ratio}.txt"

  # 8. csv 저장
  echo "[8/8] Saving csv..."
  sudo mv "$BASE_CSV" "$RESULT_DIR/result_split_${ratio}.csv"

done

echo "🎉 All split_ratio tests completed! Results in $RESULT_DIR"
