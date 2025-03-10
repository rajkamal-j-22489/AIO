#!/bin/bash

# Hadoop FIO Benchmark Script
# This script tests storage performance for Hadoop workloads on specified mount points

# Configuration variables
MOUNT_POINTS=("/disk1" "/disk2")
OUTPUT_DIR="./fio_results"
DATETIME=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${OUTPUT_DIR}/hadoop_fio_benchmark_${DATETIME}.log"
SUMMARY_FILE="${OUTPUT_DIR}/hadoop_fio_summary_${DATETIME}.txt"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Log header
echo "Hadoop FIO Benchmark Started at $(date)" | tee -a "${LOG_FILE}"
echo "===============================================" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Summary header
echo "Hadoop FIO Benchmark Summary (${DATETIME})" > "${SUMMARY_FILE}"
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
    
    # Test 1: HDFS Large File Write (DataNode write pattern)
    run_fio_test "${mount_point}" "hdfs_large_write" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=128M
        --size=4G
        --iodepth=4
        --numjobs=4
        --group_reporting"
    
    # Test 2: HDFS Large File Read (MapReduce input read pattern)
    run_fio_test "${mount_point}" "hdfs_large_read" "
        --rw=read
        --ioengine=libaio
        --direct=1
        --bs=128M
        --size=4G
        --iodepth=4
        --numjobs=4
        --group_reporting"
    
    # Test 3: HDFS Small File Write Pattern (NameNode metadata intensive)
    run_fio_test "${mount_point}" "hdfs_small_write" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=64k
        --size=2G
        --nrfiles=1000
        --file_service_type=random
        --iodepth=16
        --numjobs=8
        --sync=1
        --group_reporting"
    
    # Test 4: HDFS Small File Read Pattern (NameNode metadata intensive)
    run_fio_test "${mount_point}" "hdfs_small_read" "
        --rw=read
        --ioengine=libaio
        --direct=1
        --bs=64k
        --size=2G
        --nrfiles=1000
        --file_service_type=random
        --iodepth=16
        --numjobs=8
        --group_reporting"
    
    # Test 5: MapReduce Shuffle Phase (mixed random I/O)
    run_fio_test "${mount_point}" "mapreduce_shuffle" "
        --rw=randrw
        --rwmixread=50
        --ioengine=libaio
        --direct=1
        --bs=1M
        --size=4G
        --iodepth=16
        --numjobs=8
        --time_based
        --runtime=60
        --group_reporting"
    
    # Test 6: HDFS Block Replication (sequential writes)
    run_fio_test "${mount_point}" "hdfs_replication" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=128M
        --size=4G
        --iodepth=3
        --numjobs=3
        --rate=100m
        --group_reporting"
    
    # Test 7: NameNode Edit Log Write (sync writes)
    run_fio_test "${mount_point}" "namenode_editlog" "
        --rw=write
        --ioengine=libaio
        --direct=1
        --bs=4k
        --size=1G
        --iodepth=1
        --numjobs=1
        --fsync=1
        --group_reporting"
    
    # Test 8: YARN Temporary Storage (container logs and shuffle data)
    run_fio_test "${mount_point}" "yarn_temp_storage" "
        --rw=randrw
        --rwmixread=30
        --ioengine=libaio
        --direct=1
        --bs=256k
        --size=2G
        --iodepth=8
        --numjobs=4
        --time_based
        --runtime=60
        --group_reporting"
    
    # Test 9: HBase Random Read Workload
    run_fio_test "${mount_point}" "hbase_random_read" "
        --rw=randread
        --ioengine=libaio
        --direct=1
        --bs=64k
        --size=2G
        --iodepth=32
        --numjobs=16
        --time_based
        --runtime=60
        --group_reporting"
    
    # Test 10: Hadoop Streaming Job Pattern (sequential reads and writes)
    run_fio_test "${mount_point}" "hadoop_streaming" "
        --rw=readwrite
        --ioengine=libaio
        --direct=1
        --bs=1M
        --size=4G
        --iodepth=8
        --numjobs=4
        --group_reporting"
    
    # Clean up test directory
    rm -rf "${mount_point}/fio_test"
    
    echo "" | tee -a "${LOG_FILE}"
done

echo "Hadoop FIO Benchmark Completed at $(date)" | tee -a "${LOG_FILE}"
echo "Results saved to ${OUTPUT_DIR}" | tee -a "${LOG_FILE}"
echo "Summary saved to ${SUMMARY_FILE}" | tee -a "${LOG_FILE}"

# Display summary
echo ""
echo "Benchmark Summary:"
cat "${SUMMARY_FILE}"
