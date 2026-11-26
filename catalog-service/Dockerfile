
# Stage 1: Install production dependencies and prepare the application
FROM node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a AS builder

WORKDIR /app

# Copy dependency manifests first to improve build caching
COPY package*.json ./

# Install only production dependencies using the lockfile
RUN npm ci --omit=dev

# Copy application source
COPY src/ ./src/


# Stage 2: Minimal production runtime
FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

WORKDIR /app

# Install the C++ runtime required by Node.js
# libgcc is installed as a dependency where required
RUN apk add --no-cache libstdc++ \
    && addgroup -S node \
    && adduser -S -G node node

# Copy only the Node.js executable from the builder
COPY --from=builder /usr/local/bin/node /usr/local/bin/node

# Copy production dependencies and application source
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/src ./src

# Run as a non-root user
USER node

EXPOSE 3000

# Check Catalog API health
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

# Start the application using exec form
CMD ["node", "src/index.js"]
