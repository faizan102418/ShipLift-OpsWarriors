#!/usr/bin/env bash
set -Eeuo pipefail

# ShopLite production deployment automation
# Usage: sudo /opt/shoplite/deploy.sh <7-character-sha>

export PATH=/usr/local/bin:/usr/bin:/bin
export AWS_REGION=ap-southeast-2
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN AWS_EC2_METADATA_DISABLED
unset DOCKER_HOST DOCKER_CONTEXT

APP_DIR="/opt/shoplite"
AWS_ACCOUNT_ID="782086108297"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

APP_DOMAIN="shoplite-opswarriors.duckdns.org"
HEALTH_TIMEOUT=180

CURRENT_FILE="$APP_DIR/current.sha"
PREVIOUS_FILE="$APP_DIR/previous.sha"

SERVICES=(frontend catalog inventory orders)

log() {
    printf '[%s] [INFO] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

valid_sha() {
    [[ "$1" =~ ^[0-9a-f]{7}$ ]]
}

# --------------------------------------------------
# 1. Validate execution
# --------------------------------------------------

[[ "$EUID" -eq 0 ]] || fail "Run this script as root"

[[ "$#" -le 1 ]] || fail "Usage: $0 <release-sha>"

RELEASE_SHA="${1:-${IMAGE_TAG:-}}"

[[ -n "$RELEASE_SHA" ]] || fail "IMAGE_TAG or release SHA is required"

valid_sha "$RELEASE_SHA" || fail "Invalid release SHA"

cd "$APP_DIR"

for cmd in aws docker curl flock mktemp; do
    command -v "$cmd" >/dev/null 2>&1 ||
        fail "Missing command: $cmd"
done

# --------------------------------------------------
# 2. Prevent concurrent deployments
# --------------------------------------------------

umask 077

exec 9>"$APP_DIR/deploy.lock"

flock -n 9 || fail "Another deployment is running"

log "Deployment lock acquired"
log "Requested release: $RELEASE_SHA"

# --------------------------------------------------
# 3. Validate production configuration
# --------------------------------------------------

for file in backend.env orders.env frontend.env postgres.env; do
    [[ -f "$APP_DIR/$file" ]] ||
        fail "Missing configuration: $file"

    [[ "$(stat -c '%a:%u:%g' "$APP_DIR/$file")" == "600:0:0" ]] ||
        fail "Unsafe configuration permissions: $file"
done

docker info >/dev/null 2>&1 ||
    fail "Docker daemon is unavailable"

for network in frontend-net backend-net; do
    docker network inspect "$network" >/dev/null 2>&1 ||
        fail "Missing Docker network: $network"
done

[[ "$(docker network inspect backend-net \
    --format '{{.Internal}}')" == "true" ]] ||
    fail "Backend network is not internal"

docker volume inspect pgdata >/dev/null 2>&1 ||
    fail "Database volume is missing"

[[ "$(docker inspect postgres \
    --format '{{.State.Health.Status}}')" == "healthy" ]] ||
    fail "PostgreSQL is not healthy"

# Reject containers that do not belong to ShopLite.
for service in "${SERVICES[@]}"; do
    if docker container inspect "$service" >/dev/null 2>&1; then
        OWNER=$(docker inspect \
            --format '{{index .Config.Labels "project"}}' \
            "$service")

        [[ "$OWNER" == "shoplite" ]] ||
            fail "Container ownership conflict: $service"
    fi
done

log "Production configuration verified"

# --------------------------------------------------
# 4. Read existing release
# --------------------------------------------------

OLD_SHA=""

if [[ -f "$CURRENT_FILE" ]]; then
    OLD_SHA=$(cat "$CURRENT_FILE")
    valid_sha "$OLD_SHA" ||
        fail "Invalid current release record"

    log "Current release: $OLD_SHA"
else
    log "No previous successful deployment"
fi

# --------------------------------------------------
# 5. Authenticate with AWS ECR
# --------------------------------------------------

ACTUAL_ACCOUNT=$(aws sts get-caller-identity \
    --query Account --output text)

[[ "$ACTUAL_ACCOUNT" == "$AWS_ACCOUNT_ID" ]] ||
    fail "Unexpected AWS account"

TEMP_DOCKER_CONFIG=$(mktemp -d)

cleanup() {
    rm -rf -- "$TEMP_DOCKER_CONFIG"
}

trap cleanup EXIT

export DOCKER_CONFIG="$TEMP_DOCKER_CONFIG"

aws ecr get-login-password --region "$AWS_REGION" |
    docker login \
        --username AWS \
        --password-stdin "$ECR_REGISTRY"

log "ECR authentication successful"

# --------------------------------------------------
# 6. Download release images
# --------------------------------------------------

pull_images() {
    local sha="$1"
    local service

    for service in "${SERVICES[@]}"; do
        log "Pulling $service:$sha"

        docker pull --platform linux/amd64 \
            "$ECR_REGISTRY/shoplite/$service:$sha" ||
            return 1
    done
}

pull_images "$RELEASE_SHA" ||
    fail "Image pull failed. Running containers unchanged."

# Ensure rollback images are available before replacement.
if [[ -n "$OLD_SHA" && "$OLD_SHA" != "$RELEASE_SHA" ]]; then
    for service in "${SERVICES[@]}"; do
        docker image inspect \
            "$ECR_REGISTRY/shoplite/$service:$OLD_SHA" \
            >/dev/null 2>&1 ||
            fail "Rollback image missing: $service:$OLD_SHA"
    done
fi

log "All required images are available"

# --------------------------------------------------
# 7. Container health verification
# --------------------------------------------------

wait_healthy() {
    local container="$1"
    local deadline=$((SECONDS + HEALTH_TIMEOUT))
    local health state

    log "Waiting for $container"

    while (( SECONDS < deadline )); do
        health=$(docker inspect \
            --format '{{.State.Health.Status}}' \
            "$container" 2>/dev/null) || return 1

        state=$(docker inspect \
            --format '{{.State.Status}}' \
            "$container" 2>/dev/null) || return 1

        if [[ "$health" == "healthy" &&
              "$state" == "running" ]]; then
            log "$container is healthy"
            return 0
        fi

        if [[ "$health" == "unhealthy" ||
              "$state" == "exited" ||
              "$state" == "dead" ]]; then
            log "$container failed"
            return 1
        fi

        sleep 3
    done

    log "Health check timed out: $container"
    return 1
}

# --------------------------------------------------
# 8. Remove application containers only
# --------------------------------------------------

remove_app_containers() {
    local service owner

    # Verify ownership before removing anything.
    for service in "${SERVICES[@]}"; do
        if docker container inspect "$service" >/dev/null 2>&1; then
            owner=$(docker inspect \
                --format '{{index .Config.Labels "project"}}' \
                "$service") || return 1

            [[ "$owner" == "shoplite" ]] || return 1
        fi
    done

    for service in "${SERVICES[@]}"; do
        if docker container inspect "$service" >/dev/null 2>&1; then
            docker rm -f "$service" >/dev/null || return 1
        fi
    done
}

# --------------------------------------------------
# 9. Start backend containers
# --------------------------------------------------

start_backend() {
    local service="$1"
    local sha="$2"
    local env_file="backend.env"

    if [[ "$service" == "orders" ]]; then
        env_file="orders.env"
    fi

    log "Starting $service:$sha"

    docker run -d \
        --pull=never \
        --name "$service" \
        --label project=shoplite \
        --label "release=$sha" \
        --network backend-net \
        --restart unless-stopped \
        --env-file "$APP_DIR/$env_file" \
        "$ECR_REGISTRY/shoplite/$service:$sha" \
        >/dev/null || return 1

    docker network connect frontend-net "$service" ||
        return 1
}

# --------------------------------------------------
# 10. Start frontend container
# --------------------------------------------------

start_frontend() {
    local sha="$1"

    log "Starting frontend:$sha"

    docker run -d \
        --pull=never \
        --name frontend \
        --label project=shoplite \
        --label "release=$sha" \
        --network frontend-net \
        --restart unless-stopped \
        --env-file "$APP_DIR/frontend.env" \
        -p 0.0.0.0:80:8080 \
        "$ECR_REGISTRY/shoplite/frontend:$sha" \
        >/dev/null || return 1
}

# --------------------------------------------------
# 11. HTTP smoke tests
# --------------------------------------------------

smoke_test() {
    local path

    for path in / \
        /api/catalog/health \
        /api/inventory/health \
        /api/orders/health; do

        log "Testing $path"

        curl --fail --silent --show-error \
            --connect-timeout 5 \
            --max-time 15 \
            -H "Host: $APP_DOMAIN" \
            "http://127.0.0.1$path" \
            >/dev/null || return 1
    done

    log "All HTTP smoke tests passed"
}

# --------------------------------------------------
# 12. Deploy a release
# --------------------------------------------------

deploy_release() {
    local sha="$1"

    remove_app_containers || return 1

    start_backend catalog "$sha" || return 1
    start_backend inventory "$sha" || return 1

    wait_healthy catalog || return 1
    wait_healthy inventory || return 1

    start_backend orders "$sha" || return 1
    wait_healthy orders || return 1

    start_frontend "$sha" || return 1
    timeout 60 bash -c '
        until [[ "$(curl -s --connect-timeout 2 --max-time 3 \
            -o /dev/null -w "%{http_code}" \
            -H "Host: $1" \
            http://127.0.0.1/api/catalog/health)" == "200" ]]; do
            sleep 2
        done
    ' _ "$APP_DOMAIN" || return 1

    wait_healthy frontend || return 1

    smoke_test || return 1
}

# --------------------------------------------------
# 13. Release tracking
# --------------------------------------------------

write_release() {
    local file="$1"
    local sha="$2"
    local temp_file

    temp_file=$(mktemp "$APP_DIR/.release.XXXXXX") ||
        return 1

    printf '%s\n' "$sha" > "$temp_file" || return 1

    mv -f -- "$temp_file" "$file" || return 1
}

# --------------------------------------------------
# 14. Execute deployment and rollback if needed
# --------------------------------------------------

log "Beginning deployment: $RELEASE_SHA"

if deploy_release "$RELEASE_SHA"; then

    if [[ -n "$OLD_SHA" && "$OLD_SHA" != "$RELEASE_SHA" ]]; then
        write_release "$PREVIOUS_FILE" "$OLD_SHA" ||
            fail "Deployment running but previous SHA recording failed"
    fi

    write_release "$CURRENT_FILE" "$RELEASE_SHA" ||
        fail "Deployment running but current SHA recording failed"

    log "Deployment successful"
    log "Active release: $RELEASE_SHA"

else

    log "Deployment failed"

    if [[ -n "$OLD_SHA" ]]; then

        log "Attempting rollback to $OLD_SHA"

        if deploy_release "$OLD_SHA"; then
            log "Rollback successful"
            log "Restored release: $OLD_SHA"
        else
            fail "Rollback failed. Manual intervention required."
        fi

    else

        log "No previous release available"

        remove_app_containers ||
            fail "Failed to clean up partial deployment"

        log "Partial application deployment removed"
    fi

    exit 1
fi

log "PostgreSQL and persistent storage preserved"

# Remove old ShopLite images while protecting rollback releases.
prune_old_images() {
    local current previous cutoff service ref tag created epoch

    current=$(cat "$CURRENT_FILE")
    previous=$(cat "$PREVIOUS_FILE" 2>/dev/null || true)
    cutoff=$(date -d '7 days ago' +%s)

    for service in "${SERVICES[@]}"; do
        while IFS= read -r ref; do
            tag="${ref##*:}"

            valid_sha "$tag" || continue

            if [[ "$tag" == "$current" ||
                  "$tag" == "$previous" ]]; then
                continue
            fi

            created=$(docker image inspect \
                --format '{{.Created}}' "$ref") || continue

            epoch=$(date -d "$created" +%s) || continue

            if (( epoch < cutoff )); then
                log "Removing old image: $ref"
                docker image rm "$ref" ||
                    log "Image retained: $ref"
            fi

        done < <(
            docker image ls \
                "$ECR_REGISTRY/shoplite/$service" \
                --format '{{.Repository}}:{{.Tag}}'
        )
    done
}

prune_old_images || log "Image cleanup incomplete"

log "Deployment finished"
