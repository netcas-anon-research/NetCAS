# **netCAS**

**netCAS (Network-aware Cache-Aware Splitting)** is a Linux kernel–level extension of [OpenCAS (Open Cache Acceleration Software)](https://github.com/Open-CAS/open-cas-linux) that enables **network-aware hybrid caching**.
It dynamically distributes read operations between a **local persistent memory (PMem)** cache device and a **remote NVMe-oF (RDMA)** backing device based on real-time network conditions.

---

## **Overview**

Modern data centers often decouple application and storage nodes for scalability.
While NVMe-oF provides high throughput over RDMA, its performance still fluctuates with network contention.
netCAS extends OpenCAS to **adapt cache–backing split ratios at runtime**, ensuring optimal I/O throughput even under changing network conditions.

**Key idea:**
Instead of always hitting the cache, netCAS **splits each read I/O** between PMem and NVMe-oF according to:
[
\text{Optimal Split Ratio} = \frac{\text{IOPS}*{\text{cache}}}{\text{IOPS}*{\text{cache}} + \text{IOPS}_{\text{backing}}}
]
and dynamically adjusts it when RDMA bandwidth or latency degrades.

---

## **Architecture**

```
           ┌────────────────────────────┐
           │       User Workload        │
           └─────────────┬──────────────┘
                         │
               ┌─────────▼─────────┐
               │     OpenCAS Core   │
               │ (modified for netCAS)
               └─────────┬─────────┘
                         │
     ┌───────────────────┴──────────────────────┐
     │                                          │
┌────▼────┐                              ┌──────▼─────┐
│  PMem   │ ←── local cache device       │ NVMe-oF RDMA│ ← remote backing
│  (cache)│                              │   device    │
└─────────┘                              └─────────────┘
     │                                          │
     └──── netCAS Splitter  ← dynamic ratio ────┘
```

---

## **Key Components**

### **1. netCAS Splitter**

* Kernel-space scheduler that decides per-I/O routing.
* Supports both **Weighted Round Robin (WRR)** and **Random** modes.
* Uses lookup tables (IOPS vs. IOdepth × Jobs) pre-collected from benchmarking.

### **2. netCAS Monitor**

* Hooks into the **NVMe-oF RDMA driver** to record:

  * **Throughput (MB/s)**
  * **Average latency (µs)**
  * Exposed via `/sys/kernel/rdma_metrics/{throughput,latency}`
* Feeds these values into the splitter every 0.1 s.

### **3. Dynamic Split Ratio Logic**

* Detects **network congestion** using moving averages of RDMA metrics.

* Modes:

  | Mode           | Description                             |
  | -------------- | --------------------------------------- |
  | **IDLE**       | No active traffic; default 100 % cache  |
  | **WARMUP**     | Initial sampling window filling         |
  | **STABLE**     | Steady state, ratio applied from lookup |
  | **CONGESTION** | Detected BW/latency drop → recalc ratio |
  | **FAILURE**    | Fallback on cache-only mode             |

* Congestion detection thresholds (examples):

  * Bandwidth drop ≥ 9 %
  * Latency increase ≥ 7 %

---

## **Kernel-Level Modifications**

### **In OpenCAS (`engine_fast.c`)**

* Integrated `netcas_should_send_to_backend()` call inside the cache-hit path.
* Splitter operates transparently regardless of the OpenCAS write policy (WT/WB/WO).

### **In NVMe-oF RDMA driver**

* Added performance probes in:

  * `nvme_rdma_queue_rq()` → record request start time
  * `nvme_rdma_complete_rq()` → calculate per-I/O latency and throughput
* Aggregates per-second averages and exposes via sysfs for the monitor module.

---

## **Algorithm Summary**

1. Measure standalone IOPS for cache and backend.
2. Compute theoretical ratio:
   [
   r = \frac{A}{A + B}
   ]
3. Apply **Weighted RR**:

   * Pattern-based (e.g., 4 × cache : 1 × backend for 80:20)
   * Maintains both **short-term fairness** and **long-term ratio stability**
4. Detect RDMA congestion and reduce backend weight dynamically.

---

## **Repository Layout**

```
open-cas-linux/           →  Vanilla OpenCAS kernel module
open-cas-linux-mf/        →  OrthusCAS (Multi-Factor) variant
open-cas-linux-netCAS/    →  NetCAS: network-aware variant (modified OpenCAS)
shell/                    →  Setup & experiment scripts
test/                     →  Test and benchmark tools
```

---

## **Building**

```bash
# Choose variant
cd open-cas-linux-netCAS
make
sudo make install
```

### **Automated PMem + NVMe-oF setup**

```bash
sudo ./shell/setup_opencas_pmem.sh         # Vanilla / NetCAS
sudo ./shell/setup_opencas_pmem.sh mf      # OrthusCAS variant
```

This script:

* Detects PMem and NVMe devices
* Creates OpenCAS instances
* Connects to NVMe-oF targets (via RDMA)
* Loads appropriate kernel modules

---

## **Runtime Monitoring**

```bash
cat /sys/kernel/rdma_metrics/throughput   # MB/s
cat /sys/kernel/rdma_metrics/latency      # µs
dmesg | grep netCAS                       # Logs current mode and ratio
```

Sample kernel log output:

```
netCAS: STABLE mode - Calculated split ratio: 82.35% (RDMA: 5120 MB/s, IOPS: 120K)
netCAS: Mode changed from STABLE to CONGESTION (BW_Drop: 9%, Lat_Inc: 7%)
```

---

## **Key Features Summary**

* ✅ **Dynamic Split Ratio** based on real-time RDMA stats
* ✅ **Weighted Round Robin & Random Splitter Modes**
* ✅ **Zero user-space overhead (all in kernel)**
* ✅ **PMem + NVMe-oF hybrid caching**
* ✅ **Sysfs-based monitoring and logging**
* ✅ **Congestion-aware adaptive I/O balancing**

---

## **Reference Implementations**

* **OrthusCAS (FAST ’21)** — multi-factor caching baseline
* **netCAS (FAST ’26 submission)** — network-aware adaptive extension

---

## **License**

Based on OpenCAS (BSD 3-Clause License).
See `open-cas-linux/LICENSE`.

---

## **Acknowledgments**

* OpenCAS community (Intel, WDC, et al.) for the base caching framework
* UCLA Networking Systems Lab for guidance and testbed infrastructure

---