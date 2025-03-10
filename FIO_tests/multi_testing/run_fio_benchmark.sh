#!/bin/bash
#
# Dual Disk FIO Benchmark Script
# This script runs comprehensive FIO benchmarks on two disks and generates reports
# 
# Usage: ./run_fio_benchmark.sh [disk1_path] [disk2_path]
#   Example: ./run_fio_benchmark.sh /mnt/ssd1 /mnt/ssd2

set -e

# Default disk paths if not provided
DISK1=${1:-"/disk1"}
DISK2=${2:-"/disk2"}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="fio_results_${TIMESTAMP}"
FIO_CONFIG="dual_disk_benchmark_${TIMESTAMP}.fio"

# Check if fio is installed
if ! command -v fio &> /dev/null; then
    echo "Error: FIO is not installed. Please install it first."
    echo "Ubuntu/Debian: sudo apt-get install fio"
    echo "CentOS/RHEL: sudo yum install fio"
    exit 1
fi

# Verify disk paths exist
for DISK in "$DISK1" "$DISK2"; do
    if [ ! -d "$DISK" ]; then
        echo "Error: Directory $DISK does not exist."
        exit 1
    fi
    
    # Check for write permissions
    if [ ! -w "$DISK" ]; then
        echo "Error: No write permission on $DISK."
        exit 1
    fi
    
    # Check available space (need at least 10GB)
    AVAILABLE_SPACE=$(df -BG "$DISK" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 10 ]; then
        echo "Warning: Less than 10GB available on $DISK ($AVAILABLE_SPACE GB available)."
        echo "This might affect benchmark results or fail during execution."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            exit 1
        fi
    fi
done

# Create results directory
mkdir -p "$RESULTS_DIR"
echo "Created results directory: $RESULTS_DIR"

# Create FIO config file
cat > "$RESULTS_DIR/$FIO_CONFIG" << EOL
[global]
direct=1
ioengine=libaio
runtime=300
time_based=1
group_reporting=1
rw=randrw
rwmixread=70
size=10G
iodepth=64
numjobs=2
thread=1

[metadata-access-disk1]
description=Simulates metadata operations on disk1 (small random I/O)
stonewall
filename=${DISK1}/fio_test_file
rw=randrw
rwmixread=80
bs=4k
runtime=180
iodepth=16
numjobs=4

[metadata-access-disk2]
description=Simulates metadata operations on disk2 (small random I/O)
stonewall
filename=${DISK2}/fio_test_file
rw=randrw
rwmixread=80
bs=4k
runtime=180
iodepth=16
numjobs=4

[database-workload-disk1]
description=Simulates database workload on disk1 (8K blocks, mostly random)
stonewall
filename=${DISK1}/fio_test_file
rw=randrw
rwmixread=75
bs=8k
runtime=240
iodepth=32
numjobs=4

[database-workload-disk2]
description=Simulates database workload on disk2 (8K blocks, mostly random)
stonewall
filename=${DISK2}/fio_test_file
rw=randrw
rwmixread=75
bs=8k
runtime=240
iodepth=32
numjobs=4

[file-server-disk1]
description=Simulates file server workload on disk1 (mixed block sizes)
stonewall
filename=${DISK1}/fio_test_file
rw=randrw
rwmixread=80
bs=4k
runtime=240
iodepth=16
numjobs=2

[file-server-disk2]
description=Simulates file server workload on disk2 (mixed block sizes)
stonewall
filename=${DISK2}/fio_test_file
rw=randrw
rwmixread=80
bs=4k
runtime=240
iodepth=16
numjobs=2

[streaming-reads-disk1]
description=Simulates large sequential reads on disk1 (video/backup)
stonewall
filename=${DISK1}/fio_test_file
rw=read
bs=1m
runtime=180
iodepth=8
numjobs=1

[streaming-reads-disk2]
description=Simulates large sequential reads on disk2 (video/backup)
stonewall
filename=${DISK2}/fio_test_file
rw=read
bs=1m
runtime=180
iodepth=8
numjobs=1

[streaming-writes-disk1]
description=Simulates large sequential writes on disk1 (backup/logging)
stonewall
filename=${DISK1}/fio_test_file
rw=write
bs=1m
runtime=180
iodepth=8
numjobs=1

[streaming-writes-disk2]
description=Simulates large sequential writes on disk2 (backup/logging)
stonewall
filename=${DISK2}/fio_test_file
rw=write
bs=1m
runtime=180
iodepth=8
numjobs=1

[mixed-workload-disk1]
description=Random mix with various block sizes and depths on disk1
stonewall
filename=${DISK1}/fio_test_file
rw=randrw
rwmixread=60
bs=64k
runtime=300
iodepth=32
numjobs=4

[mixed-workload-disk2]
description=Random mix with various block sizes and depths on disk2
stonewall
filename=${DISK2}/fio_test_file
rw=randrw
rwmixread=60
bs=64k
runtime=300
iodepth=32
numjobs=4

[latency-test-disk1]
description=Tests I/O latency with small QD on disk1
stonewall
filename=${DISK1}/fio_test_file
rw=randrw
rwmixread=70
bs=4k
runtime=120
iodepth=1
numjobs=1

[latency-test-disk2]
description=Tests I/O latency with small QD on disk2
stonewall
filename=${DISK2}/fio_test_file
rw=randrw
rwmixread=70
bs=4k
runtime=120
iodepth=1
numjobs=1
EOL

echo "Created FIO configuration file: $RESULTS_DIR/$FIO_CONFIG"

# Display system information
echo "Collecting system information..."
{
    echo "# System Information"
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo ""
    echo "## CPU Information"
    lscpu | grep -E "Model name|Socket|Core|Thread|CPU MHz"
    echo ""
    echo "## Memory Information"
    free -h
    echo ""
    echo "## Disk Information"
    echo "### Disk 1: $DISK1"
    df -h "$DISK1"
    echo ""
    echo "### Disk 2: $DISK2"
    df -h "$DISK2"
    echo ""
    if command -v lsblk &> /dev/null; then
        echo "## Block Device Information"
        lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL
        echo ""
    fi
} > "$RESULTS_DIR/system_info.txt"

echo "System information saved to: $RESULTS_DIR/system_info.txt"

# Run the benchmark
echo "Starting FIO benchmark. This will take some time..."
echo "Benchmark configuration: $RESULTS_DIR/$FIO_CONFIG"
echo "Results will be stored in: $RESULTS_DIR"

# Save start time
START_TIME=$(date +%s)

# Run FIO with the created config and save output to a text file
fio "$RESULTS_DIR/$FIO_CONFIG" --output="$RESULTS_DIR/fio_results.txt"

# Optionally run with JSON output if the version supports it
if fio --version | grep -q "fio-3"; then
    # FIO version 3+ supports JSON output
    fio "$RESULTS_DIR/$FIO_CONFIG" --output-format=json --output="$RESULTS_DIR/fio_results.json" || true
fi

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(( (ELAPSED % 3600) / 60 ))
SECONDS=$((ELAPSED % 60))

# Create summary report
{
    echo "# FIO Benchmark Summary"
    echo "Completed at: $(date)"
    echo "Total runtime: ${HOURS}h ${MINUTES}m ${SECONDS}s"
    echo ""
    echo "## Test Configuration"
    echo "Disk 1: $DISK1"
    echo "Disk 2: $DISK2"
    echo "Configuration file: $FIO_CONFIG"
    echo ""
    echo "## Key Results"
    echo "For detailed results, please check fio_results.txt"
    echo ""
    echo "### Results Summary"
    echo ""
    echo "#### Raw Results (first 20 lines):"
    head -n 20 "$RESULTS_DIR/fio_results.txt"
    echo "..."
    echo ""
    echo "Full results available in the results directory."
} > "$RESULTS_DIR/benchmark_summary.md"

echo "Benchmark complete!"
echo "Summary report: $RESULTS_DIR/benchmark_summary.md"
echo "Detailed results: $RESULTS_DIR/fio_results.txt"

# Clean up test files (optional)
read -p "Do you want to remove the test files from disks? (y/n): " CLEANUP
if [ "$CLEANUP" == "y" ]; then
    rm -f "${DISK1}/fio_test_file" "${DISK2}/fio_test_file"
    echo "Test files removed."
fi

echo "Done!"
