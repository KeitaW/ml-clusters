#!/bin/bash
set -euo pipefail

echo "=== HyperPod Lifecycle Script: on_create ==="

# Configure Slurm (for Slurm orchestrator)
if command -v slurmctld &> /dev/null || command -v slurmd &> /dev/null; then
    echo "Configuring Slurm environment..."

    # Set NCCL environment variables for optimal multi-node training
    cat >> /etc/environment << 'NCCL_ENV'
NCCL_DEBUG=INFO
NCCL_SOCKET_IFNAME=eth0
NCCL_PROTO=Simple
FI_PROVIDER=efa
FI_EFA_USE_DEVICE_RDMA=1
NCCL_ENV

    # Configure EFA
    echo "Setting up EFA..."
    if [ -d /opt/amazon/efa ]; then
        echo "EFA already installed"
        /opt/amazon/efa/bin/fi_info -p efa -t FI_EP_RDM 2>/dev/null && echo "EFA operational" || echo "EFA check failed"
    fi

    # Set up shared directories
    mkdir -p /fsx/checkpoints /fsx/datasets /fsx/models
    chmod 755 /fsx/checkpoints /fsx/datasets /fsx/models
fi

echo "=== Lifecycle script completed ==="
