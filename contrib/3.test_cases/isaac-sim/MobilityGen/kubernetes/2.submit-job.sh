#!/bin/bash
# Submit the MobilityGen SDG job to Kubernetes
#
# Prerequisites:
#   - kubectl configured for your EKS cluster
#   - NGC secret created (0.setup-ngc-secret.sh)
#   - Container image built and pushed (1.build-container.sh)
#
# Environment variables:
#   IMAGE_URI          - Container image URI (required)
#   NAMESPACE          - K8s namespace (default: isaac-sim)
#   NUM_TRAJECTORIES   - Number of trajectories (default: 5)
#   INSTANCE_TYPE      - GPU instance type hint (default: g5.4xlarge)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${IMAGE_URI:-}" ]; then
    echo "ERROR: IMAGE_URI environment variable is not set."
    echo "Run 1.build-container.sh first, then: export IMAGE_URI=<uri>"
    exit 1
fi

export NAMESPACE="${NAMESPACE:-isaac-sim}"
export NUM_TRAJECTORIES="${NUM_TRAJECTORIES:-5}"
export INSTANCE_TYPE="${INSTANCE_TYPE:-g5.4xlarge}"

echo "=== Submitting MobilityGen SDG Job ==="
echo "  Image:        ${IMAGE_URI}"
echo "  Namespace:    ${NAMESPACE}"
echo "  Trajectories: ${NUM_TRAJECTORIES}"
echo "  Instance:     ${INSTANCE_TYPE}"

envsubst < "${SCRIPT_DIR}/mobilitygen-job.yaml-template" | kubectl apply -f -

echo ""
echo "Job submitted. Monitor with:"
echo "  kubectl logs -f job/mobilitygen-sdg -n ${NAMESPACE}"
echo "  kubectl get pods -n ${NAMESPACE} -w"
