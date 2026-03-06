#!/bin/bash
# Build and push the MobilityGen container image to Amazon ECR
#
# Prerequisites:
#   - Docker installed and running
#   - AWS CLI configured with ECR push permissions
#   - NGC_API_KEY set (to pull base image from nvcr.io)

set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="${ECR_REPO_NAME:-isaac-sim-mobilitygen}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${IMAGE_TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(dirname "${SCRIPT_DIR}")"

echo "=== Building MobilityGen container ==="
echo "  Region:    ${REGION}"
echo "  Account:   ${ACCOUNT_ID}"
echo "  Image URI: ${IMAGE_URI}"

# Authenticate to NGC (base image)
if [ -n "${NGC_API_KEY:-}" ]; then
    echo "Logging in to NGC registry..."
    echo "${NGC_API_KEY}" | docker login nvcr.io --username '$oauthtoken' --password-stdin
fi

# Create ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names "${REPO_NAME}" --region "${REGION}" 2>/dev/null || \
    aws ecr create-repository --repository-name "${REPO_NAME}" --region "${REGION}"

# Authenticate to ECR
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Build and push
echo "Building image..."
docker build -t "${IMAGE_URI}" "${BUILD_DIR}"

echo "Pushing image..."
docker push "${IMAGE_URI}"

echo "=== Image pushed: ${IMAGE_URI} ==="
echo ""
echo "Export for use with submit script:"
echo "  export IMAGE_URI=${IMAGE_URI}"
