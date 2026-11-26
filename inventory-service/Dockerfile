# Stage 1: Build the Go application
FROM golang:1.26-alpine@sha256:ecb67f987aa1a57794c91d19ade7ae0209f2f0f5496aaef9e6ae85ddf92d02ab AS builder

WORKDIR /app

# Copy dependency manifests first for build caching
COPY go.mod go.sum ./

# Download Go dependencies
RUN go mod download

# Copy application source
COPY main.go ./

# Build a statically linked, optimized binary
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /inventory ./main.go


# Stage 2: Minimal production runtime
FROM scratch

WORKDIR /

COPY --from=builder /inventory /inventory

# Run as non-root
USER 65532:65532

EXPOSE 8081

# Use the application's built-in healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["/inventory", "-healthcheck"]

ENTRYPOINT ["/inventory"]
