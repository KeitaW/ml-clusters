#!/bin/bash
set -euo pipefail

echo "=== HyperPod EKS Lifecycle Script: on_create ==="

# Set NCCL environment variables for optimal multi-node training
cat >> /etc/environment << 'NCCL_ENV'
NCCL_DEBUG=INFO
NCCL_SOCKET_IFNAME=eth0
NCCL_PROTO=Simple
FI_PROVIDER=efa
FI_EFA_USE_DEVICE_RDMA=1
NCCL_ENV

echo "=== EKS lifecycle script completed ==="
