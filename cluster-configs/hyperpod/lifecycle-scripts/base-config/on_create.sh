#!/bin/bash
set -euo pipefail

echo "=== HyperPod Lifecycle Script: on_create ==="
echo "Instance type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo 'unknown')"

# Load provisioning parameters if available
PROV_PARAMS="/opt/ml/config/resource_config.json"
if [ -f "$PROV_PARAMS" ]; then
    echo "Resource config found at $PROV_PARAMS"
fi

###############################################################################
# NCCL + EFA Environment
###############################################################################
echo "Configuring NCCL and EFA environment..."

cat >> /etc/environment << 'NCCL_ENV'
NCCL_DEBUG=INFO
NCCL_SOCKET_IFNAME=eth0
NCCL_PROTO=Simple
FI_PROVIDER=efa
FI_EFA_USE_DEVICE_RDMA=1
NCCL_ENV

# Source environment for current session
set -a
source /etc/environment
set +a

###############################################################################
# EFA Verification
###############################################################################
echo "Verifying EFA..."
if [ -d /opt/amazon/efa ]; then
    echo "EFA installed: $(/opt/amazon/efa/bin/fi_info --version 2>/dev/null || echo 'version unknown')"
    /opt/amazon/efa/bin/fi_info -p efa -t FI_EP_RDM 2>/dev/null && echo "EFA operational" || echo "EFA RDM check failed (may be expected on non-EFA instances)"
else
    echo "EFA not installed (expected for non-GPU instances)"
fi

###############################################################################
# FSx Mount
###############################################################################
LIFECYCLE_SCRIPTS_DIR=$(dirname "$(readlink -f "$0")")
PROV_PARAMS_JSON="${LIFECYCLE_SCRIPTS_DIR}/provisioning_parameters.json"

if [ -f "$PROV_PARAMS_JSON" ]; then
    FSX_DNS=$(python3 -c "import json; d=json.load(open('${PROV_PARAMS_JSON}')); print(d.get('fsx_dns_name',''))" 2>/dev/null || echo "")
    FSX_MOUNT=$(python3 -c "import json; d=json.load(open('${PROV_PARAMS_JSON}')); print(d.get('fsx_mount_name',''))" 2>/dev/null || echo "")

    if [ -n "$FSX_DNS" ] && [ -n "$FSX_MOUNT" ]; then
        echo "Mounting FSx: ${FSX_DNS}@tcp:/${FSX_MOUNT} -> /fsx"
        mkdir -p /fsx
        if ! mountpoint -q /fsx; then
            mount -t lustre -o relatime,flock "${FSX_DNS}@tcp:/${FSX_MOUNT}" /fsx
            echo "${FSX_DNS}@tcp:/${FSX_MOUNT} /fsx lustre defaults,relatime,flock,_netdev 0 0" >> /etc/fstab
        fi
    fi
fi

# Create standard directories on FSx or local
for dir in /fsx/checkpoints /fsx/datasets /fsx/models /fsx/logs; do
    mkdir -p "$dir" 2>/dev/null || true
done
chmod 755 /fsx/checkpoints /fsx/datasets /fsx/models /fsx/logs 2>/dev/null || true

###############################################################################
# Slurm Configuration (Slurm orchestrator only)
###############################################################################
if command -v slurmctld &> /dev/null || command -v slurmd &> /dev/null; then
    echo "Detected Slurm environment"

    # Enable Slurm accounting if MariaDB is available
    if command -v mysql &> /dev/null; then
        echo "MariaDB available, accounting can be configured via slurm.conf"
    fi
fi

echo "=== Lifecycle script completed ==="
