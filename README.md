# netCAS

netCAS is a network-aware caching system based on OpenCAS (Open Cache Acceleration Software). This repository contains modifications to the OpenCAS Linux kernel module to support network-aware caching functionality.

## Overview

netCAS extends the OpenCAS caching framework to provide network-aware caching capabilities, allowing for intelligent cache placement and management based on network conditions and topology.

## Open-CAS Variants

This repository contains three variants of Open-CAS:

1. **Vanilla Open-CAS** (`open-cas-linux/`) - The original unmodified OpenCAS Linux implementation
2. **OrthusCAS (MF variant)** (`open-cas-linux-mf/`) - Modified version with multi-factor (MF) caching capabilities
3. **NetCAS** (`open-cas-linux-netCAS/`) - Our network-aware caching implementation with advanced features for distributed caching

Each variant can be built and configured independently based on your caching requirements.

## Repository Structure

- `open-cas-linux/` - Vanilla Open-CAS Linux kernel module
- `open-cas-linux-mf/` - OrthusCAS (MF variant) implementation
- `open-cas-linux-netCAS/` - NetCAS implementation with network-aware enhancements
- `shell/` - Shell scripts for setup, teardown, and management of netCAS components
- `test/` - Test files and utilities

## Key Features

- Network-aware cache placement
- Dynamic cache mode switching based on network conditions
- RDMA and NVMe-oF support
- PMEM (Persistent Memory) integration
- Advanced split ratio optimization

## Getting Started

### Prerequisites

- Linux kernel headers
- Build tools (make, gcc)
- RDMA drivers (for RDMA functionality)
- NVMe drivers (for NVMe-oF functionality)

### Building and Setup

You can build and set up any of the Open-CAS variants using the automated setup script:

```bash
# For Vanilla Open-CAS or NetCAS
sudo ./shell/setup_opencas_pmem.sh

# For OrthusCAS (MF variant)
sudo ./shell/setup_opencas_pmem.sh mf
```

The `setup_opencas_pmem.sh` script automatically:
- Verifies PMEM and NVMe device availability
- Creates cache instances using PMEM
- Adds NVMe as the core device
- Configures cache modes (including MF-specific modes for OrthusCAS)

#### Manual Building

Alternatively, you can manually build any variant:

```bash
# Choose your variant
cd open-cas-linux          # Vanilla
# or
cd open-cas-linux-mf       # OrthusCAS
# or
cd open-cas-linux-netCAS   # NetCAS

# Build
make

# Install
sudo make install
```

## Usage

See the `shell/` directory for additional setup and management scripts:

- `setup_opencas.sh` - Basic OpenCAS setup
- `setup_opencas_pmem.sh` - Automated setup with PMEM support (supports all variants)
- `setup_rdma.sh` - Setup with RDMA support
- `connect-nvme.sh` - Connect to NVMe-oF targets
- `connect-rdma.sh` - Connect to RDMA targets

## License

This project is based on [OpenCAS](https://github.com/Open-CAS/open-cas-linux), which is licensed under the BSD 3-Clause License. See the LICENSE file in the `open-cas-linux/` directory for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Contact

For questions and contributions, please contact the netCAS development team.

## Acknowledgments

This project is based on the OpenCAS project by Intel. We thank the OpenCAS community for their excellent work on the caching framework.
