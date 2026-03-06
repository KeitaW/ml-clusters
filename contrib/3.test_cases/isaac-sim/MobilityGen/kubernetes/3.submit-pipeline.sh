#!/bin/bash
# Submit the full AMR Navigation Pipeline as an OSMO workflow
#
# Prerequisites:
#   - kubectl configured for your EKS cluster
#   - OSMO installed on the cluster
#   - NGC secret created (0.setup-ngc-secret.sh)
#   - All 3 container images built and pushed (1.build-container.sh)
#   - S3 bucket created with IRSA configured
#
# Environment variables:
#   ISAAC_SIM_IMAGE_URI  - Isaac Sim AMR image (stages 1-4) (required)
#   COSMOS_IMAGE_URI     - Cosmos Transfer image (stage 5) (required)
#   XMOBILITY_IMAGE_URI  - X-Mobility training image (stage 6) (required)
#   S3_BUCKET            - S3 bucket for pipeline data (required)
#   RUN_ID               - Pipeline run identifier (default: timestamp)
#   NAMESPACE            - K8s namespace (default: isaac-sim)
#   NUM_TRAJECTORIES     - Number of trajectories (default: 10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate required variables
for var in ISAAC_SIM_IMAGE_URI COSMOS_IMAGE_URI XMOBILITY_IMAGE_URI S3_BUCKET; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: ${var} environment variable is not set."
        exit 1
    fi
done

export NAMESPACE="${NAMESPACE:-isaac-sim}"
export RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
export NUM_TRAJECTORIES="${NUM_TRAJECTORIES:-10}"

echo "=== Submitting AMR Navigation Pipeline ==="
echo "  Isaac Sim Image: ${ISAAC_SIM_IMAGE_URI}"
echo "  Cosmos Image:    ${COSMOS_IMAGE_URI}"
echo "  X-Mobility Image: ${XMOBILITY_IMAGE_URI}"
echo "  S3 Bucket:       ${S3_BUCKET}"
echo "  Run ID:          ${RUN_ID}"
echo "  Namespace:       ${NAMESPACE}"
echo "  Trajectories:    ${NUM_TRAJECTORIES}"

# Apply IRSA ServiceAccount
echo ""
echo "--- Setting up ServiceAccount ---"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
envsubst < "${SCRIPT_DIR}/serviceaccount.yaml" | kubectl apply -f -

# Submit OSMO workflow
echo ""
echo "--- Submitting OSMO Workflow ---"
envsubst < "${SCRIPT_DIR}/amr-pipeline-workflow.yaml" | kubectl apply -f -

echo ""
echo "=== Pipeline submitted ==="
echo ""
echo "Monitor with:"
echo "  kubectl get workflows -n ${NAMESPACE} -w"
echo "  kubectl get pods -n ${NAMESPACE} -w"
echo ""
echo "Check stage logs:"
echo "  kubectl logs -f -l osmo.nvidia.com/workflow=amr-navigation-pipeline -n ${NAMESPACE}"
echo ""
echo "S3 output path:"
echo "  s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/"
