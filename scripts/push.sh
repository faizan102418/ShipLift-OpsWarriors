#!/usr/bin/env bash

set -Eeuo pipefail

# ==========================================
# ShopLite - Build and Push Images to AWS ECR
# ==========================================

# Move to repository root
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Configuration
export AWS_REGION="${AWS_REGION:-ap-southeast-2}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""
export AWS_EC2_METADATA_DISABLED=true

EXPECTED_ACCOUNT="782086108297"
EXPECTED_REGION="ap-southeast-2"
PLATFORM="linux/amd64"

SERVICES=(frontend catalog inventory orders)

declare -A CONTEXTS=(
    [frontend]="./frontend"
    [catalog]="./catalog-service"
    [inventory]="./inventory-service"
    [orders]="./order-service"
)

# Logging functions
log() {
    printf '[INFO] %s\n' "$*"
}

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

# Verify required tools
for cmd in aws docker git; do
    command -v "$cmd" >/dev/null 2>&1 \
        || fail "$cmd is not installed"
done

docker info >/dev/null 2>&1 \
    || fail "Docker daemon is unavailable"

docker buildx version >/dev/null 2>&1 \
    || fail "Docker Buildx is unavailable"

# Require a clean Git working tree
if [[ -n "$(git status --porcelain)" ]]; then
    fail "Commit your changes before publishing images"
fi

# Verify AWS identity
AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

[[ "$AWS_ACCOUNT_ID" == "$EXPECTED_ACCOUNT" ]] \
    || fail "Unexpected AWS account: $AWS_ACCOUNT_ID"

[[ "$AWS_REGION" == "$EXPECTED_REGION" ]] \
    || fail "Unexpected AWS region: $AWS_REGION"

# Generate release information
FULL_SHA=$(git rev-parse HEAD)
IMAGE_TAG="${FULL_SHA:0:7}"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

log "AWS account: $AWS_ACCOUNT_ID"
log "AWS region: $AWS_REGION"
log "Release tag: $IMAGE_TAG"
log "Platform: $PLATFORM"

# Isolate temporary Docker authentication
TEMP_DOCKER_CONFIG=$(mktemp -d)

cleanup() {
    rm -rf -- "$TEMP_DOCKER_CONFIG"
}

trap cleanup EXIT

# Authenticate with ECR
log "Authenticating with AWS ECR"

aws ecr get-login-password \
    --region "$AWS_REGION" |
    docker --config "$TEMP_DOCKER_CONFIG" login \
        --username AWS \
        --password-stdin "$ECR_REGISTRY"

# Build and publish each service
for service in "${SERVICES[@]}"; do

    REPOSITORY="shoplite/$service"
    IMAGE_URI="${ECR_REGISTRY}/${REPOSITORY}:${IMAGE_TAG}"
    CONTEXT="${CONTEXTS[$service]}"

    log "Processing $service"

    [[ -f "$CONTEXT/Dockerfile" ]] \
        || fail "Dockerfile missing: $CONTEXT"

    # Check whether this immutable tag exists
    if RESULT=$(aws ecr describe-images \
        --repository-name "$REPOSITORY" \
        --image-ids imageTag="$IMAGE_TAG" \
        --output json 2>&1); then

        log "Tag already exists. Verifying source revision."

        docker --config "$TEMP_DOCKER_CONFIG" pull \
            --platform "$PLATFORM" "$IMAGE_URI"

        EXISTING_SHA=$(docker image inspect \
            --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' \
            "$IMAGE_URI")

        [[ "$EXISTING_SHA" == "$FULL_SHA" ]] \
            || fail "Existing image revision cannot be verified: $IMAGE_URI"

        log "Verified existing image. Skipping $service"
        continue

    elif [[ "$RESULT" != *ImageNotFoundException* ]]; then

        fail "Unable to check ECR image: $RESULT"

    fi

    # Build image
    log "Building $IMAGE_URI"

    docker buildx build \
        --platform "$PLATFORM" \
        --label "org.opencontainers.image.revision=$FULL_SHA" \
        --tag "$IMAGE_URI" \
        --load \
        "$CONTEXT"

    # Push image
    log "Pushing $IMAGE_URI"

    docker --config "$TEMP_DOCKER_CONFIG" push "$IMAGE_URI"

    log "$service published successfully"

done

# Verify all four images exist
for service in "${SERVICES[@]}"; do

    DIGEST=$(aws ecr describe-images \
        --repository-name "shoplite/$service" \
        --image-ids imageTag="$IMAGE_TAG" \
        --query 'imageDetails[0].imageDigest' \
        --output text)

    log "$service: $DIGEST"

done

log "All four images published successfully"
log "Release tag: $IMAGE_TAG"
