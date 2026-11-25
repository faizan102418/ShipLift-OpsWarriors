FROM node:22-alpine

WORKDIR /app

# Copy dependency manifests first for better build-cache usage
COPY package*.json ./

# Install production dependencies from the lockfile
RUN npm ci --omit=dev

# Copy application source code
COPY --chown=node:node src/ ./src/

# Run the application as a non-root user
USER node

EXPOSE 3000

# Check whether the Catalog API is responding
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "src/index.js"]
