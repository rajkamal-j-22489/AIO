#!/bin/bash

# MySQL FIO Benchmark Script
# This script tests storage performance for MySQL workloads on specified mount points

# Configuration variables
MOUNT_POINTS=("/disk1" "/disk2")
OUTPUT_DIR="./fio_results"
DATETIME=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${OUTPUT_DIR}/mysql_fio_benchmark_${DATETIME}.log"
SUMMARY_FILE="${OUTPUT_DIR}/mysql_fio_summary_${DATETIME}.txt"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Log header
echo "MySQL FIO Benchmark Started at $(date)" | tee -a "${LOG_FILE}"
echo "===============================================" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Summary header
echo "MySQL FIO Benchmark Summary (${DATETIME})" > "${SUMMARY_FILE}"
echo "===============================================" >> "${SUMMARY_FILE}"
echo "" >> "${SUMMARY_FILE}"

# Function to run FIO tests and capture results
run_fio_test() {
    local mount_point=$1
    local test_name=$2
    local fio_params=$3
    local output_file="${OUTPUT_DIR}/fio_${test_name}_$(basename ${mount_point})_${DATETIME}.json"

    echo "Running test: ${test_name} on ${mount_point}" | tee -a "${LOG_FILE}"
    echo "Output file: ${output_file}" | tee -a "${LOG_FILE}"
    
    # Create test directory if it doesn't exist
    local test_dir="${mount_point}/fio_test"
    mkdir -p "${test_dir}"
    
    # Run the FIO test
    fio --directory="${test_dir}" \
        --name="${test_name}" \
        --output-format=json \
        --output="${output_file}" \
        ${fio_params}
    
    # Extract and log key metrics
    if [ -f "${output_file}" ]; then
        local read_iops=$(jq '.jobs[0].read.iops' "${output_file}")
        local write_iops=$(jq '.jobs[0].write.iops' "${output_file}")
        local read_bw=$(jq '.jobs[0].read.bw' "${output_file}")
        local write_bw=$(jq '.jobs[0].write.bw' "${output_file}")
        local read_lat=$(jq '.jobs[0].read.lat_ns.mean/1000' "${output_file}")
        local write_lat=$(jq '.jobs[0].write.lat_ns.mean/1000' "${output_file}")
        
        echo "  Results:" | tee -a "${LOG_FILE}"
        echo "    Read IOPS: ${read_iops}" | tee -a "${LOG_FILE}"
        echo "    Write IOPS: ${write_iops}" | tee -a "${LOG_FILE}"
        echo "    Read Bandwidth: ${read_bw} KB/s" | tee -a "${LOG_FILE}"
        echo "    Write Bandwidth: ${write_bw} KB/s" | tee -a "${LOG_FILE}"
        echo "    Read Latency: ${read_lat} μs" | tee -a "${LOG_FILE}"
        echo "    Write Latency: ${write_lat} μs" | tee -a "${LOG_FILE}"
        echo "" | tee -a "${LOG_FILE}"
        
        # Add to summary
        echo "Test: ${test_name} on ${mount_point}" >> "${SUMMARY_FILE}"
        echo "  Read IOPS: ${read_iops}" >> "${SUMMARY_FILE}"
        echo "  Write IOPS: ${write_iops}" >> "${SUMMARY_FILE}"
        echo "  Read Bandwidth: ${read_bw} KB/s" >> "${SUMMARY_FILE}"
        echo "  Write Bandwidth: ${write_bw} KB/s" >> "${SUMMARY_FILE}"
        echo "  Read Latency: ${read_lat} μs" >> "${SUMMARY_FILE}"
        echo "  Write Latency: ${write_lat} μs" >> "${SUMMARY_FILE}"
        echo "" >> "${SUMMARY_FILE}"
    else
        echo "  Error: Test failed or output file not created" | tee -a "${LOG_FILE}"
        echo "" | tee -a "${LOG_FILE}"
    fi
}

# Check if fio is installed
if ! command -v fio &> /dev/null; then
    echo "Error: FIO is not installed. Please install it first." | tee -a "${LOG_FILE}"
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it first." | tee -a "${LOG_FILE}"
    exit 1
fi

# Run tests on each mount point
for mount_point in "${MOUNT_POINTS[@]}"; do
    echo "Testing mount point: ${mount_point}" | tee -a "${LOG_FILE}"
    echo "===============================================" | tee -a "${LOG_FILE}"
    
    # Check if mount point exists
    if [ ! -d "${mount_point}" ]; then
        echo "Error: Mount point ${mount_point} does not exist." | tee -a "${LOG_FILE}"
        continue
    fi
    
    # Test 1: MySQL InnoDB Log File Simulation (sequential writes)
    run_fio_test "${mount_point}" "mysql_innodb_log" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=16k
        --size=1G
        --iodepth=4
        --numjobs=1
        --fsync=1
        --group_reporting"
    
    # Test 2: MySQL InnoDB Data File Random Read
    run_fio_test "${mount_point}" "mysql_random_read" "
        --rw=randread
        --ioengine=libaio
        --direct=1
        --bs=16k
        --size=1G
        --iodepth=64
        --numjobs=4
        --time_based
        --runtime=60
        --group_reporting"
    
    # Test 3: MySQL InnoDB Data File Random Write
    run_fio_test "${mount_point}" "mysql_random_write" "
        --rw=randwrite
        --ioengine=libaio
        --direct=1
        --bs=16k
        --size=1G
        --iodepth=64
        --numjobs=4
        --time_based
        --runtime=60
        --group_reporting"
    
    # Test 4: MySQL Mixed Workload (70% read, 30% write)
    run_fio_test "${mount_point}" "mysql_mixed_workload" "
        --rw=randrw
        --rwmixread=70
        --ioengine=libaio
        --direct=1
        --bs=16k
        --size=1G
        --iodepth=64
        --numjobs=4
        --time_based
        --runtime=60
        --group_reporting"
    
    # Test 5: MySQL Insert Workload Simulation (large sequential writes)
    run_fio_test "${mount_point}" "mysql_insert_workload" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=128k
        --size=1G
        --iodepth=8
        --numjobs=2
        --fsync_on_close=1
        --group_reporting"
        
    # Test 6: MySQL Database Backup Simulation (large sequential reads)
    run_fio_test "${mount_point}" "mysql_backup_workload" "
        --rw=read
        --ioengine=libaio
        --direct=1
        --bs=1M
        --size=2G
        --iodepth=16
        --numjobs=1
        --group_reporting"
        
    # Test 7: MySQL Index Scan Simulation (random reads with small block size)
    run_fio_test "${mount_point}" "mysql_index_scan" "
        --rw=randread
        --ioengine=libaio
        --direct=1
        --bs=4k
        --size=1G
        --iodepth=32
        --numjobs=4
        --time_based
        --runtime=60
        --group_reporting"
        
    # Test 8: MySQL Table Scan Simulation (sequential reads)
    run_fio_test "${mount_point}" "mysql_table_scan" "
        --rw=read
        --ioengine=libaio
        --direct=1
        --bs=64k
        --size=1G
        --iodepth=16
        --numjobs=2
        --time_based
        --runtime=60
        --group_reporting"
        
    # Test 9: MySQL Write-Heavy OLTP Workload (30% read, 70% write)
    run_fio_test "${mount_point}" "mysql_write_heavy_oltp" "
        --rw=randrw
        --rwmixread=30
        --ioengine=libaio
        --direct=1
        --bs=8k
        --size=1G
        --iodepth=32
        --numjobs=4
        --time_based
        --runtime=60
        --group_reporting"
        
    # Test 10: MySQL Binary Log Writes (sequential writes with fsync)
    run_fio_test "${mount_point}" "mysql_binlog_writes" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=4k
        --size=512M
        --iodepth=1
        --numjobs=1
        --fsync=1
        --group_reporting"
    
    # Clean up test directory
    rm -rf "${mount_point}/fio_test"
    
    echo "" | tee -a "${LOG_FILE}"
done

echo "MySQL FIO Benchmark Completed at $(date)" | tee -a "${LOG_FILE}"
echo "Results saved to ${OUTPUT_DIR}" | tee -a "${LOG_FILE}"
echo "Summary saved to ${SUMMARY_FILE}" | tee -a "${LOG_FILE}"

# Display summary
echo ""
echo "Benchmark Summary:"
cat "${SUMMARY_FILE}"
