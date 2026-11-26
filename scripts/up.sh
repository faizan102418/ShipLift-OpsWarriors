
#!/usr/bin/env bash
set -Eeuo pipefail

# ShopLite startup automation
# Usage: TAG=1.0.0 ./scripts/up.sh

TAG="${TAG:-1.0.0}"
HEALTH_TIMEOUT=60

echo "=================================="
echo "       Starting ShopLite"
echo "       Image tag: $TAG"
echo "=================================="

# Check required environment file
if [[ ! -f .env ]]; then
    echo "ERROR: .env file not found in project root."
    exit 1
fi

# Check required images
for service in frontend catalog inventory orders; do
    if ! docker image inspect "shop-${service}:${TAG}" >/dev/null 2>&1; then
        echo "ERROR: Missing image shop-${service}:${TAG}"
        exit 1
    fi
done

# Create networks only if they do not exist
if ! docker network inspect backend-net >/dev/null 2>&1; then
    echo "Creating internal backend-net..."
    docker network create --driver bridge --internal backend-net
fi

if ! docker network inspect frontend-net >/dev/null 2>&1; then
    echo "Creating frontend-net..."
    docker network create --driver bridge frontend-net
fi

# Create database volume only if it does not exist
if ! docker volume inspect pgdata >/dev/null 2>&1; then
    echo "Creating pgdata volume..."
    docker volume create pgdata
fi

# Wait for a container to become healthy
wait_healthy() {
    local container="$1"
    local elapsed=0
    local status

    echo "Waiting for $container to become healthy..."

    while (( elapsed < HEALTH_TIMEOUT )); do
        status=$(docker inspect \
            --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)

        if [[ "$status" == "healthy" ]]; then
            echo "$container is healthy."
            return 0
        fi

        if [[ "$status" == "unhealthy" ]]; then
            echo "ERROR: $container is unhealthy."
            docker logs --tail 20 "$container"
            return 1
        fi

        if [[ "$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)" == "exited" ]]; then
            echo "ERROR: $container exited unexpectedly."
            docker logs --tail 20 "$container"
            return 1
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "ERROR: Timed out waiting for $container."
    docker logs --tail 20 "$container"
    return 1
}

# Remove existing project containers before recreating them
echo "Removing existing ShopLite containers..."
docker rm -f frontend orders inventory catalog postgres >/dev/null 2>&1 || true

# Start PostgreSQL
echo "Starting PostgreSQL..."
docker run -d \
    --name postgres \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    -v pgdata:/var/lib/postgresql/data \
    -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro" \
    --health-cmd='pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    --health-interval=10s \
    --health-timeout=5s \
    --health-retries=5 \
    postgres:17-alpine >/dev/null

wait_healthy postgres

# Start Catalog
echo "Starting Catalog..."
docker run -d \
    --name catalog \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    "shop-catalog:${TAG}" >/dev/null

# Start Inventory
echo "Starting Inventory..."
docker run -d \
    --name inventory \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    "shop-inventory:${TAG}" >/dev/null

# Start Orders
echo "Starting Orders..."
docker run -d \
    --name orders \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    "shop-orders:${TAG}" >/dev/null

# Attach backends to frontend network
docker network connect frontend-net catalog
docker network connect frontend-net inventory
docker network connect frontend-net orders

# Wait for all backend services
wait_healthy catalog
wait_healthy inventory
wait_healthy orders

# Start Frontend last
echo "Starting Frontend..."
docker run -d \
    --name frontend \
    --network frontend-net \
    --restart unless-stopped \
    --env-file .env \
    -p 80:8080 \
    "shop-frontend:${TAG}" >/dev/null

wait_healthy frontend

echo "=================================="
echo "ShopLite started successfully!"
echo "Open: http://shoplite.test"
echo "=================================="
