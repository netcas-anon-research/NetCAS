#!/bin/bash

set -e

# 스크립트가 있는 디렉토리를 기준으로 상대 경로 계산
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

KERNEL_SRC="/usr/src/linux-5.4.43"
NVME_DIR="$KERNEL_SRC/drivers/nvme"
MODULE_DIR="$NVME_DIR/host"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [original|modified]"
  exit 1
fi

VARIANT=$1
if [ "$VARIANT" == "original" ]; then
  RDMA_SRC="$SCRIPT_DIR/nvme/host/rdma.c"
elif [ "$VARIANT" == "modified" ]; then
  RDMA_SRC="$SCRIPT_DIR/nvme-modified/host/rdma.c"
else
  echo "❌ Invalid argument: $VARIANT"
  exit 1
fi

if [ ! -f "$RDMA_SRC" ]; then
  echo "❌ Source file $RDMA_SRC not found."
  exit 1
fi

echo "[0/6] Copying $VARIANT version of rdma.c..."
sudo cp -f "$RDMA_SRC" "$MODULE_DIR/rdma.c"

echo "[1/6] Rebuilding all NVMe modules..."
make -C "$KERNEL_SRC" M="$NVME_DIR" modules

echo "[2/6] Copying to /lib/modules..."
sudo cp "$MODULE_DIR"/nvme-core.ko /lib/modules/5.4.43/kernel/drivers/nvme/host/
sudo cp "$MODULE_DIR"/nvme.ko /lib/modules/5.4.43/kernel/drivers/nvme/host/
sudo cp "$MODULE_DIR"/nvme-fabrics.ko /lib/modules/5.4.43/kernel/drivers/nvme/host/
sudo cp "$MODULE_DIR"/nvme-rdma.ko /lib/modules/5.4.43/kernel/drivers/nvme/host/

echo "[3/6] Running depmod..."
sudo depmod -a

echo "[4/6] Removing old modules..."
sudo modprobe -r nvme_rdma nvme_fabrics nvme nvme_core 2>/dev/null || true

echo "[5/6] Inserting rebuilt modules..."
sudo modprobe nvme_core
sudo modprobe nvme
sudo modprobe nvme_fabrics
sudo modprobe nvme_rdma

echo "✅ [$VARIANT] NVMe RDMA modules loaded!"