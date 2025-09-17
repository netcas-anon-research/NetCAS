#!/usr/bin/env python3
"""
netCAS CPU Usage Analysis Tool
Analyzes CPU usage by different categories for netCAS system
"""

import re
import json
import argparse
from collections import defaultdict, Counter
from pathlib import Path
import matplotlib.pyplot as plt
import pandas as pd

class NetCASCPUCategorizer:
    def __init__(self):
        # Define CPU usage categories based on netCAS architecture
        # Define CPU usage categories with priority order (most specific first)
        self.categories = {
            'fio': {
                'keywords': ['fio_', 'aio_', 'io_submit', 'io_getevents', 'io_cancel', 'io_setup', 'io_destroy'],
                'dsos': [],  # No specific DSO for FIO
                'description': 'FIO workload and I/O operations',
                'color': '#FF6B6B',
                'priority': 1
            },
            'opencas': {
                'keywords': ['cas_', 'casdsk', 'ocf_', 'cache_', 'lru_', 'metadata_', 'netcas_', 'splitter', 'engine_', 'cas_bd_', 'ocf_submit_volume_req_cmpl', '_ocf_read_wo_core_complete', 'ocf_req_complete'],
                'dsos': ['cas_cache', 'cas_disk'],
                'description': 'OpenCAS and netCAS operations',
                'color': '#4ECDC4',
                'priority': 2
            },
            'nvme': {
                'keywords': ['nvme_', 'nvme_rdma', 'ib_', 'mlx5_', 'irq_poll_', '__ib_process_cq', 'ib_poll_handler', 'irq_poll_complete', 'irq_poll_sched', 'blk_mq_complete_request', 'blk_mq_end_request', 'kworker', 'events'],
                'dsos': ['mlx5_ib', 'ib_core', 'mlx5_core', 'nvme', 'nvme_core'],
                'description': 'NVMe driver, NVMe-oF RDMA operations, and related kernel workers',
                'color': '#45B7D1',
                'priority': 3
            },
            'block_io': {
                'keywords': ['blk_', 'bio_', 'blkdev_', 'block_dev_', 'request_', 'generic_make_request', 'submit_bio', 'generic_file_read_iter'],
                'dsos': [],
                'description': 'Block-layer core (generic blk/bio/mq)',
                'color': '#FFEAA7',
                'priority': 4
            },
            'filesystem': {
                'keywords': ['ext4_', 'xfs_', 'btrfs_', 'filemap_', 'do_filp_open', 'page_mkwrite'],
                'dsos': [],
                'description': 'Filesystem and VFS operations',
                'color': '#DDA0DD',
                'priority': 5
            },
            'os': {
                'keywords': [
                    # Interrupts/softirq
                    '__do_softirq', 'irq_poll_', 'handle_irq_event', 'ksoftirqd', 'tasklet_', 'softirq', 'do_IRQ', 'irq_exit', 'ret_from_intr',
                    # Scheduler
                    'schedule', '__sched_text_start', 'enqueue_task', 'ttwu_do_activate', 'ttwu_', 'psi_task_change', '__wake_up', 'wake_up', '__wake_up_common', 'autoremove_wake_function', 'activate_task', 'try_to_wake_up', 'schedule_idle',
                    # Syscalls and kernel services
                    'do_syscall_64', 'entry_SYSCALL_64', 'start_secondary', 'vprintk', 'printk'
                ],
                'dsos': [],
                'description': 'Operating system: scheduler, interrupts/softirq, syscalls, kernel services',
                'color': '#87CEFA',
                'priority': 6
            },
            'pmem': {
                'keywords': ['pmem_', 'dax_', 'nvdimm', 'memmap', 'env_allocator_', 'get_user_pages_', 'iov_iter_', 'set_page_dirty_'],
                'dsos': [],
                'description': 'Persistent Memory and memory management operations',
                'color': '#FFA07A',
                'priority': 8
            },
            'idle': {
                'keywords': ['do_idle', 'cpuidle_', 'cpuidle', 'acpi_idle_', 'cpu_startup_entry'],
                'dsos': [],
                'description': 'CPU idle and power management',
                'color': '#E6E6FA',
                'priority': 9
            },
            'other': {
                'keywords': [],
                'dsos': [],
                'description': 'Other operations',
                'color': '#F8F9FA',
                'priority': 10
            }
        }
        
        self.category_stats = defaultdict(lambda: {'samples': 0, 'percentage': 0.0, 'functions': Counter()})
        self.total_active_cpu = None
        self.avg_memory_used = None
        self.avg_context_switches = None
        self.avg_interrupts = None
        self.avg_block_reads = None
        self.avg_block_writes = None
        
    def categorize_function(self, function_name, shared_object=None):
        """Categorize a function based on DSO first, then keywords, with priority resolution"""
        function_lower = function_name.lower()
        shared_object_lower = shared_object.lower() if shared_object else ""
        
        # Track all matching categories for priority resolution
        matching_categories = []
        
        for category, info in self.categories.items():
            if category == 'other':
                continue
            
            # Check DSO first (highest priority)
            if shared_object and info['dsos']:
                for dso in info['dsos']:
                    if dso.lower() in shared_object_lower:
                        matching_categories.append((category, info['priority']))
                        break
            
            # Check keywords if no DSO match
            if not matching_categories or not info['dsos']:
                for keyword in info['keywords']:
                    if keyword.lower() in function_lower:
                        matching_categories.append((category, info['priority']))
                        break
        
        # Return the highest priority match (lowest priority number)
        if matching_categories:
            # Sort by priority (ascending) and return the first (highest priority)
            matching_categories.sort(key=lambda x: x[1])
            return matching_categories[0][0]
        
        return 'other'
    
    def parse_perf_report(self, perf_file):
        """Parse perf report and categorize CPU usage"""
        print(f"Parsing perf report: {perf_file}")
        
        with open(perf_file, 'r') as f:
            content = f.read()
        
        # Parse the perf report format
        # Look for lines with percentage and function names
        lines = content.split('\n')
        
        for line in lines:
            # Match lines like: "    46.62%     0.00%  swapper          [kernel.vmlinux]                                 [k] 0xffffffff822000e6"
            # or lines with function names
            if '%' in line and '[' in line:
                # Extract percentage and function info
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        percentage = float(parts[0].replace('%', ''))
                        if percentage > 0.1:  # Only consider significant percentages
                            # Look for function name in the line
                            function_match = re.search(r'--(\d+\.\d+)%--([a-zA-Z_][a-zA-Z0-9_]*)', line)
                            if function_match:
                                func_percentage = float(function_match.group(1))
                                function_name = function_match.group(2)
                                
                                # Extract shared object from the line if available
                                shared_object = None
                                dso_match = re.search(r'\[([^\]]+)\]', line)
                                if dso_match:
                                    shared_object = dso_match.group(1)
                                
                                category = self.categorize_function(function_name, shared_object)
                                self.category_stats[category]['samples'] += 1
                                self.category_stats[category]['percentage'] += func_percentage
                                self.category_stats[category]['functions'][function_name] += func_percentage
                                
                    except ValueError:
                        continue
        
        # Also look for direct function calls in the call stack
        for line in lines:
            if '--' in line and '%' in line:
                # Extract function calls from call stacks
                function_calls = re.findall(r'--(\d+\.\d+)%--([a-zA-Z_][a-zA-Z0-9_]*)', line)
                for percentage, function in function_calls:
                    try:
                        func_percentage = float(percentage)
                        if func_percentage > 0.1:
                            # Extract shared object from the line if available
                            shared_object = None
                            dso_match = re.search(r'\[([^\]]+)\]', line)
                            if dso_match:
                                shared_object = dso_match.group(1)
                            
                            category = self.categorize_function(function, shared_object)
                            self.category_stats[category]['samples'] += 1
                            self.category_stats[category]['percentage'] += func_percentage
                            self.category_stats[category]['functions'][function] += func_percentage
                    except ValueError:
                        continue
    
    def parse_system_logs(self, log_dir):
        """Parse system logs for additional CPU usage information"""
        log_path = Path(log_dir)
        
        # Parse mpstat.log for overall CPU usage
        mpstat_file = log_path / 'mpstat.log'
        if mpstat_file.exists():
            print(f"Parsing mpstat log: {mpstat_file}")
            self.parse_mpstat_log(mpstat_file)
        
        # Parse vmstat.log for system-wide stats
        vmstat_file = log_path / 'vmstat.log'
        if vmstat_file.exists():
            print(f"Parsing vmstat log: {vmstat_file}")
            self.parse_vmstat_log(vmstat_file)
        
        # Parse iostat.log for block I/O stats
        iostat_file = log_path / 'iostat.log'
        if iostat_file.exists():
            print(f"Parsing iostat log: {iostat_file}")
            self.parse_iostat_log(iostat_file)
    
    def parse_mpstat_log(self, mpstat_file):
        """Parse mpstat log for CPU usage breakdown"""
        with open(mpstat_file, 'r') as f:
            lines = f.readlines()
        
        # Skip header lines and find data lines
        data_lines = []
        for line in lines:
            # Look for lines with time format or data rows
            if re.search(r'\d{2}:\d{2}:\d{2}', line) or (re.search(r'\d+\.\d+', line) and 'all' in line):
                data_lines.append(line)
        
        if data_lines:
            # Calculate averages
            total_user = 0
            total_system = 0
            total_softirq = 0
            count = 0
            
            for line in data_lines:
                parts = line.split()
                if len(parts) >= 10:
                    try:
                        # Find the 'all' column and read values after it
                        if 'all' in parts:
                            all_idx = parts.index('all')
                            if all_idx + 6 < len(parts):
                                total_user += float(parts[all_idx + 1])  # %usr
                                total_system += float(parts[all_idx + 3])  # %sys
                                total_softirq += float(parts[all_idx + 6])  # %soft
                                count += 1
                    except (ValueError, IndexError):
                        continue
            
            if count > 0:
                avg_user = total_user / count
                avg_system = total_system / count
                avg_softirq = total_softirq / count
                total_active = avg_user + avg_system + avg_softirq
                
                print(f"Average CPU Usage from mpstat:")
                print(f"  User: {avg_user:.2f}%")
                print(f"  System: {avg_system:.2f}%")
                print(f"  SoftIRQ: {avg_softirq:.2f}%")
                print(f"  Total Active: {total_active:.2f}%")
                
                # Store for absolute calculations
                self.total_active_cpu = total_active

    def compute_active_cpu_from_mpstat(self, mpstat_file):
        """Compute average total active CPU percentage (user + system + softirq) from mpstat log"""
        with open(mpstat_file, 'r') as f:
            lines = f.readlines()

        # Keep lines that look like data rows and contain the aggregate 'all' CPU
        data_lines = [line for line in lines if (' all ' in line or line.strip().endswith(' all')) and (re.search(r'\d', line) is not None)]

        if not data_lines:
            return None

        total_user = 0.0
        total_system = 0.0
        total_softirq = 0.0
        count = 0

        for line in data_lines:
            parts = line.split()
            # Find 'all' aggregate column and read standard fields relative to it
            try:
                idx_all = parts.index('all')
            except ValueError:
                continue

            # After 'all': %usr, %nice, %sys, %iowait, %irq, %soft, ...
            idx_usr = idx_all + 1
            idx_sys = idx_all + 3
            idx_soft = idx_all + 6

            if len(parts) > idx_soft:
                try:
                    total_user += float(parts[idx_usr])
                    total_system += float(parts[idx_sys])
                    total_softirq += float(parts[idx_soft])
                    count += 1
                except ValueError:
                    continue

        if count == 0:
            return None

        return (total_user + total_system + total_softirq) / count
    
    def parse_vmstat_log(self, vmstat_file):
        """Parse vmstat log for system-wide statistics"""
        with open(vmstat_file, 'r') as f:
            lines = f.readlines()
        
        # Skip header lines
        data_lines = [line for line in lines if re.match(r'^\s*\d+', line)]
        
        if data_lines:
            # Calculate averages for context switches, interrupts, and memory
            total_cs = 0
            total_in = 0
            total_free = 0
            total_used = 0
            count = 0
            
            for line in data_lines:
                parts = line.split()
                if len(parts) >= 12:
                    try:
                        total_cs += int(parts[11])  # Context switches
                        total_in += int(parts[10])  # Interrupts
                        total_free += int(parts[3])  # Free memory
                        total_used += int(parts[2])  # Used memory
                        count += 1
                    except ValueError:
                        continue
            
            if count > 0:
                avg_cs = total_cs / count
                avg_in = total_in / count
                avg_free = total_free / count
                avg_used = total_used / count
                
                print(f"Average System Activity from vmstat:")
                print(f"  Context Switches/sec: {avg_cs:.0f}")
                print(f"  Interrupts/sec: {avg_in:.0f}")
                print(f"  Free Memory (KB): {avg_free:.0f}")
                print(f"  Used Memory (KB): {avg_used:.0f}")
                
                # Store for absolute calculations
                self.avg_memory_used = avg_used
                self.avg_context_switches = avg_cs
                self.avg_interrupts = avg_in
    
    def parse_iostat_log(self, iostat_file):
        """Parse iostat log for block I/O statistics"""
        with open(iostat_file, 'r') as f:
            lines = f.readlines()
        
        # Find data lines (skip headers)
        data_lines = []
        for line in lines:
            # Look for lines with device names and numeric data
            if re.search(r'[a-zA-Z0-9]+', line) and re.search(r'\d+\.\d+', line):
                parts = line.split()
                if len(parts) >= 6 and parts[0] != 'Device:':
                    data_lines.append(line)
        
        if data_lines:
            total_reads = 0
            total_writes = 0
            count = 0
            
            for line in data_lines:
                parts = line.split()
                if len(parts) >= 6:
                    try:
                        # iostat format: Device, tps, kB_read/s, kB_wrtn/s, kB_read, kB_wrtn
                        reads_per_sec = float(parts[2])  # kB_read/s
                        writes_per_sec = float(parts[3])  # kB_wrtn/s
                        total_reads += reads_per_sec
                        total_writes += writes_per_sec
                        count += 1
                    except (ValueError, IndexError):
                        continue
            
            if count > 0:
                avg_reads = total_reads / count
                avg_writes = total_writes / count
                
                print(f"Average Block I/O from iostat:")
                print(f"  Read Rate (kB/s): {avg_reads:.2f}")
                print(f"  Write Rate (kB/s): {avg_writes:.2f}")
                
                # Store for absolute calculations
                self.avg_block_reads = avg_reads
                self.avg_block_writes = avg_writes
    
    def generate_report(self):
        """Generate comprehensive CPU usage report"""
        print("\n" + "="*60)
        print("netCAS CPU Usage Analysis Report")
        print("="*60)
        
        # Calculate total percentage
        total_percentage = sum(stats['percentage'] for stats in self.category_stats.values())
        
        if total_percentage > 0:
            # Normalize percentages
            for category in self.category_stats:
                if total_percentage > 0:
                    self.category_stats[category]['percentage'] = (
                        self.category_stats[category]['percentage'] / total_percentage * 100
                    )
        
        # Sort categories by percentage
        sorted_categories = sorted(
            self.category_stats.items(),
            key=lambda x: x[1]['percentage'],
            reverse=True
        )
        
        print(f"\nCPU Usage by Category:")
        print("-" * 50)
        
        # Show both percentage and absolute values if available
        if self.total_active_cpu is not None:
            print(f"Total Active CPU: {self.total_active_cpu:.2f}%")
            print("-" * 50)
        
        # Show absolute system metrics
        if self.avg_memory_used is not None:
            print(f"Average Memory Used: {self.avg_memory_used:.0f} KB")
        if self.avg_context_switches is not None:
            print(f"Average Context Switches/sec: {self.avg_context_switches:.0f}")
        if self.avg_interrupts is not None:
            print(f"Average Interrupts/sec: {self.avg_interrupts:.0f}")
        if self.avg_block_reads is not None and self.avg_block_writes is not None:
            print(f"Average Block I/O - Reads: {self.avg_block_reads:.2f} kB/s, Writes: {self.avg_block_writes:.2f} kB/s")
        
        if any([self.total_active_cpu, self.avg_memory_used, self.avg_context_switches, self.avg_interrupts, self.avg_block_reads]):
            print("-" * 50)
        
        for category, stats in sorted_categories:
            if stats['percentage'] > 0:
                # Calculate absolute CPU usage if total active CPU is available
                if self.total_active_cpu is not None:
                    absolute_cpu = (stats['percentage'] / 100) * self.total_active_cpu
                    print(f"{category.replace('_', ' ').title():<25}: {stats['percentage']:6.2f}% ({absolute_cpu:6.2f}% abs) ({stats['samples']:4d} samples)")
                else:
                    print(f"{category.replace('_', ' ').title():<25}: {stats['percentage']:6.2f}% ({stats['samples']:4d} samples)")
                
                # Show top functions in each category
                if stats['functions']:
                    top_functions = stats['functions'].most_common(3)
                    for func, percentage in top_functions:
                        normalized_pct = (percentage / total_percentage * 100) if total_percentage > 0 else 0
                        if self.total_active_cpu is not None:
                            abs_cpu = (normalized_pct / 100) * self.total_active_cpu
                            print(f"  └─ {func:<30}: {normalized_pct:6.2f}% ({abs_cpu:6.2f}% abs)")
                        else:
                            print(f"  └─ {func:<30}: {normalized_pct:6.2f}%")
        
        print(f"\nTotal Samples Analyzed: {sum(stats['samples'] for stats in self.category_stats.values())}")
        
        return sorted_categories
    
    def create_visualization(self, output_dir):
        """Create visualizations of CPU usage"""
        output_path = Path(output_dir)
        output_path.mkdir(exist_ok=True)
        
        # Prepare data for plotting
        categories = []
        percentages = []
        colors = []
        
        for category, stats in self.category_stats.items():
            if stats['percentage'] > 0:
                categories.append(category.replace('_', ' ').title())
                percentages.append(stats['percentage'])
                colors.append(self.categories[category]['color'])
        
        if not percentages:
            print("No data to visualize")
            return
        
        # Create bar chart only
        plt.figure(figsize=(12, 8))
        
        bars = plt.bar(categories, percentages, color=colors)
        plt.title('netCAS CPU Usage by Category', fontsize=16, fontweight='bold')
        plt.ylabel('Percentage (%)', fontsize=12)
        plt.xlabel('CPU Usage Categories', fontsize=12)
        plt.xticks(rotation=45, ha='right')
        
        # Add value labels on bars
        for bar, percentage in zip(bars, percentages):
            height = bar.get_height()
            plt.text(bar.get_x() + bar.get_width()/2., height + 0.5,
                    f'{percentage:.1f}%', ha='center', va='bottom', fontweight='bold')
        
        plt.grid(axis='y', alpha=0.3)
        plt.tight_layout()
        plt.savefig(output_path / 'netcas_cpu_usage.png', dpi=300, bbox_inches='tight')
        print(f"Visualization saved to: {output_path / 'netcas_cpu_usage.png'}")
        
        # Create detailed CSV report
        self.create_csv_report(output_path)
        
        plt.show()
    
    def create_csv_report(self, output_path):
        """Create detailed CSV report of CPU usage"""
        report_data = []
        
        for category, stats in self.category_stats.items():
            if stats['percentage'] > 0:
                # Get top functions for this category
                top_functions = []
                if stats['functions']:
                    top_functions = [f"{func} ({pct:.2f}%)" 
                                   for func, pct in stats['functions'].most_common(5)]
                
                # Calculate absolute CPU usage if available
                absolute_cpu = None
                if self.total_active_cpu is not None:
                    absolute_cpu = (stats['percentage'] / 100) * self.total_active_cpu
                
                row_data = {
                    'Category': category.replace('_', ' ').title(),
                    'Percentage': f"{stats['percentage']:.2f}%",
                    'Samples': stats['samples'],
                    'Top_Functions': '; '.join(top_functions),
                    'Description': self.categories[category]['description']
                }
                
                if absolute_cpu is not None:
                    row_data['Absolute_CPU_%'] = f"{absolute_cpu:.2f}%"
                
                report_data.append(row_data)
        
        # Add system metrics summary
        if any([self.total_active_cpu, self.avg_memory_used, self.avg_context_switches, self.avg_interrupts, self.avg_block_reads]):
            system_metrics = {
                'Category': 'System_Metrics',
                'Percentage': 'N/A',
                'Samples': 'N/A',
                'Top_Functions': 'N/A',
                'Description': 'System-wide absolute metrics'
            }
            
            if self.total_active_cpu is not None:
                system_metrics['Absolute_CPU_%'] = f"{self.total_active_cpu:.2f}%"
            if self.avg_memory_used is not None:
                system_metrics['Memory_Used_KB'] = f"{self.avg_memory_used:.0f}"
            if self.avg_context_switches is not None:
                system_metrics['Context_Switches_per_sec'] = f"{self.avg_context_switches:.0f}"
            if self.avg_interrupts is not None:
                system_metrics['Interrupts_per_sec'] = f"{self.avg_interrupts:.0f}"
            if self.avg_block_reads is not None:
                system_metrics['Block_Reads_kB_per_sec'] = f"{self.avg_block_reads:.2f}"
            if self.avg_block_writes is not None:
                system_metrics['Block_Writes_kB_per_sec'] = f"{self.avg_block_writes:.2f}"
            
            report_data.append(system_metrics)
        
        if report_data:
            df = pd.DataFrame(report_data)
            csv_file = output_path / 'netcas_cpu_analysis.csv'
            df.to_csv(csv_file, index=False)
            print(f"Detailed report saved to: {csv_file}")
    
    def analyze_performance_metrics(self, results_file):
        """Analyze performance metrics from results file"""
        if Path(results_file).exists():
            with open(results_file, 'r') as f:
                content = f.read()
            
            print(f"\nPerformance Metrics:")
            print("-" * 30)
            
            # Extract IOPS
            iops_match = re.search(r'IOPS: ([\d.]+)', content)
            if iops_match:
                iops = float(iops_match.group(1))
                print(f"IOPS: {iops:,.0f}")
            
            # Extract bandwidth
            bw_match = re.search(r'Bandwidth \(KB/s\): ([\d.]+)', content)
            if bw_match:
                bandwidth_kb = float(bw_match.group(1))
                bandwidth_gb = bandwidth_kb / (1024 * 1024)
                print(f"Bandwidth: {bandwidth_gb:.2f} GB/s")
            
            # Extract test completion time
            time_match = re.search(r'Test completed at: (.+)', content)
            if time_match:
                print(f"Test completed: {time_match.group(1)}")

def main():
    parser = argparse.ArgumentParser(description='Analyze netCAS CPU usage by category')
    parser.add_argument('test_dir', help='Test directory containing perf_report.txt, mpstat.log, vmstat.log, and results.txt')
    parser.add_argument('--output-dir', help='Output directory for reports and visualizations (default: <test_dir>_analysis)')
    parser.add_argument('--no-viz', action='store_true', help='Skip visualization generation')
    parser.add_argument('--compare-baseline', help='Baseline test directory (vanilla OpenCAS) to compare')
    parser.add_argument('--compare-variant', help='Variant test directory (mf_CAS) to compare')
    parser.add_argument('--compare-output-dir', help='Output directory for comparison reports')
    
    args = parser.parse_args()
    
    # If comparison mode is requested, run comparison and exit
    if args.compare_baseline and args.compare_variant:
        baseline_dir = Path(args.compare_baseline)
        variant_dir = Path(args.compare_variant)
        if not baseline_dir.exists() or not baseline_dir.is_dir():
            print(f"Error: Baseline directory '{baseline_dir}' does not exist or is not a directory")
            return 1
        if not variant_dir.exists() or not variant_dir.is_dir():
            print(f"Error: Variant directory '{variant_dir}' does not exist or is not a directory")
            return 1

        compare_output = Path(args.compare_output_dir) if args.compare_output_dir else Path('cpu_analysis_output-comparison')
        compare_output.mkdir(exist_ok=True)

        def compute_stats_for_dir(directory: Path):
            perf_file = directory / 'perf_report.txt'
            if not perf_file.exists():
                print(f"Error: perf_report.txt not found in '{directory}'")
                return None
            analyzer = NetCASCPUCategorizer()
            analyzer.parse_perf_report(perf_file)
            return analyzer

        baseline_analyzer = compute_stats_for_dir(baseline_dir)
        variant_analyzer = compute_stats_for_dir(variant_dir)
        if baseline_analyzer is None or variant_analyzer is None:
            return 1

        def build_normalized_category_map(analyzer: 'NetCASCPUCategorizer'):
            total_pct = sum(s['percentage'] for s in analyzer.category_stats.values())
            result = {}
            for cat, s in analyzer.category_stats.items():
                if s['percentage'] > 0 and total_pct > 0:
                    result[cat] = s['percentage'] / total_pct * 100
            return result

        def build_normalized_function_map(analyzer: 'NetCASCPUCategorizer'):
            total_pct = sum(s['percentage'] for s in analyzer.category_stats.values())
            fn_to_pct = {}
            fn_to_cat = {}
            if total_pct <= 0:
                return fn_to_pct, fn_to_cat
            for cat, s in analyzer.category_stats.items():
                for fn, raw_pct in s['functions'].items():
                    norm = raw_pct / total_pct * 100
                    fn_to_pct[fn] = fn_to_pct.get(fn, 0.0) + norm
                    # Prefer the category that contributed the most for this function
                    if fn not in fn_to_cat or s['functions'][fn] > analyzer.category_stats.get(fn_to_cat[fn], {'functions': {}})['functions'].get(fn, 0):
                        fn_to_cat[fn] = cat
            return fn_to_pct, fn_to_cat

        # Build maps
        base_cat = build_normalized_category_map(baseline_analyzer)
        var_cat = build_normalized_category_map(variant_analyzer)
        base_fn, base_fn_cat = build_normalized_function_map(baseline_analyzer)
        var_fn, var_fn_cat = build_normalized_function_map(variant_analyzer)

        # Compute absolute CPU usage from mpstat (total active) and derive absolute per-category CPU
        baseline_mpstat = baseline_dir / 'mpstat.log'
        variant_mpstat = variant_dir / 'mpstat.log'
        baseline_active = baseline_analyzer.compute_active_cpu_from_mpstat(baseline_mpstat) if baseline_mpstat.exists() else None
        variant_active = variant_analyzer.compute_active_cpu_from_mpstat(variant_mpstat) if variant_mpstat.exists() else None

        # Category comparison CSV
        category_rows = []
        all_cats = set(base_cat.keys()) | set(var_cat.keys())
        for cat in sorted(all_cats):
            b = base_cat.get(cat, 0.0)
            v = var_cat.get(cat, 0.0)
            d = v - b
            category_rows.append({
                'Category': cat.replace('_', ' ').title(),
                'Baseline_%': f"{b:.2f}",
                'Variant_%': f"{v:.2f}",
                'Delta_% (Variant-Baseline)': f"{d:.2f}",
                'Description': baseline_analyzer.categories.get(cat, {}).get('description', '')
            })
        df_cat = pd.DataFrame(category_rows)
        if not df_cat.empty:
            df_cat['abs_delta'] = df_cat['Delta_% (Variant-Baseline)'].astype(float).abs()
            df_cat = df_cat.sort_values('abs_delta', ascending=False).drop(columns=['abs_delta'])
            df_cat.to_csv(compare_output / 'category_comparison.csv', index=False)
            print(f"Category comparison saved to: {compare_output / 'category_comparison.csv'}")

        # Absolute category CPU comparison (if mpstat was available)
        if baseline_active is not None and variant_active is not None:
            abs_rows = []
            all_cats_abs = set(base_cat.keys()) | set(var_cat.keys())
            for cat in sorted(all_cats_abs):
                share_b = base_cat.get(cat, 0.0)
                share_v = var_cat.get(cat, 0.0)
                abs_b = baseline_active * share_b / 100.0
                abs_v = variant_active * share_v / 100.0
                abs_rows.append({
                    'Category': cat.replace('_', ' ').title(),
                    'Baseline_Active_Total_%': f"{baseline_active:.2f}",
                    'Variant_Active_Total_%': f"{variant_active:.2f}",
                    'Baseline_Category_%Share': f"{share_b:.2f}",
                    'Variant_Category_%Share': f"{share_v:.2f}",
                    'Baseline_Category_Absolute_%': f"{abs_b:.2f}",
                    'Variant_Category_Absolute_%': f"{abs_v:.2f}",
                    'Delta_Absolute_% (Variant-Baseline)': f"{(abs_v - abs_b):.2f}"
                })
            df_abs = pd.DataFrame(abs_rows)
            if not df_abs.empty:
                df_abs['abs_delta'] = df_abs['Delta_Absolute_% (Variant-Baseline)'].astype(float).abs()
                df_abs = df_abs.sort_values('abs_delta', ascending=False).drop(columns=['abs_delta'])
                df_abs.to_csv(compare_output / 'category_comparison_absolute.csv', index=False)
                print(f"Absolute category comparison saved to: {compare_output / 'category_comparison_absolute.csv'}")
                # Also print total active delta summary
                print(f"Total Active CPU: baseline={baseline_active:.2f}% variant={variant_active:.2f}% delta={(variant_active - baseline_active):.2f}%")

        # Function deltas CSV (top by absolute delta)
        fn_rows = []
        all_fns = set(base_fn.keys()) | set(var_fn.keys())
        for fn in all_fns:
            b = base_fn.get(fn, 0.0)
            v = var_fn.get(fn, 0.0)
            d = v - b
            cat = var_fn_cat.get(fn) or base_fn_cat.get(fn) or 'other'
            fn_rows.append({
                'Function': fn,
                'Category': cat.replace('_', ' ').title(),
                'Baseline_%': f"{b:.2f}",
                'Variant_%': f"{v:.2f}",
                'Delta_% (Variant-Baseline)': f"{d:.2f}"
            })
        df_fn = pd.DataFrame(fn_rows)
        if not df_fn.empty:
            df_fn['abs_delta'] = df_fn['Delta_% (Variant-Baseline)'].astype(float).abs()
            df_fn = df_fn.sort_values('abs_delta', ascending=False).drop(columns=['abs_delta'])
            # Save top 100 deltas
            df_fn.head(100).to_csv(compare_output / 'function_deltas_top100.csv', index=False)
            print(f"Function deltas saved to: {compare_output / 'function_deltas_top100.csv'}")

        # OpenCAS-only function deltas
        if 'opencas' in baseline_analyzer.categories:
            df_fn_opencas = df_fn[df_fn['Category'].str.lower() == 'opencas'] if not df_fn.empty else pd.DataFrame()
            if not df_fn_opencas.empty:
                df_fn_opencas = df_fn_opencas.copy()
                df_fn_opencas['abs_delta'] = df_fn_opencas['Delta_% (Variant-Baseline)'].astype(float).abs()
                df_fn_opencas = df_fn_opencas.sort_values('abs_delta', ascending=False).drop(columns=['abs_delta'])
                df_fn_opencas.head(100).to_csv(compare_output / 'opencas_function_deltas_top100.csv', index=False)
                print(f"OpenCAS function deltas saved to: {compare_output / 'opencas_function_deltas_top100.csv'}")

        print(f"\nComparison complete! Check '{compare_output}' for CSV reports.")
        return 0

    # Validate test directory
    test_dir = Path(args.test_dir)
    if not test_dir.exists() or not test_dir.is_dir():
        print(f"Error: Test directory '{test_dir}' does not exist or is not a directory")
        return 1
    
    # Auto-detect files in test directory
    perf_file = test_dir / 'perf_report.txt'
    mpstat_file = test_dir / 'mpstat.log'
    vmstat_file = test_dir / 'vmstat.log'
    results_file = test_dir / 'results.txt'
    
    # Check required files
    if not perf_file.exists():
        print(f"Error: perf_report.txt not found in '{test_dir}'")
        return 1
    
    # Set default output directory if not specified
    if not args.output_dir:
        args.output_dir = f"{test_dir.name}_analysis"
    
    print(f"Test directory: {test_dir}")
    print(f"Output directory: {args.output_dir}")
    print(f"Files found:")
    print(f"  perf_report.txt: {'✓' if perf_file.exists() else '✗'}")
    print(f"  mpstat.log: {'✓' if mpstat_file.exists() else '✗'}")
    print(f"  vmstat.log: {'✓' if vmstat_file.exists() else '✗'}")
    print(f"  results.txt: {'✓' if results_file.exists() else '✗'}")
    print()
    
    # Initialize analyzer
    analyzer = NetCASCPUCategorizer()
    
    # Parse perf report
    analyzer.parse_perf_report(perf_file)
    
    # Parse system logs if available
    if mpstat_file.exists() or vmstat_file.exists():
        analyzer.parse_system_logs(test_dir)
    
    # Analyze performance metrics if available
    if results_file.exists():
        analyzer.analyze_performance_metrics(results_file)
    
    # Generate report
    categories = analyzer.generate_report()
    
    # Always create output directory and CSV report
    output_path = Path(args.output_dir)
    output_path.mkdir(exist_ok=True)
    analyzer.create_csv_report(output_path)
    
    # Create visualizations unless disabled
    if not args.no_viz:
        analyzer.create_visualization(args.output_dir)
    
    print(f"\nAnalysis complete! Check '{args.output_dir}' directory for detailed reports.")
    return 0

if __name__ == "__main__":
    main()

