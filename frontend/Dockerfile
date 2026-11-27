# Stage 1: Build React/Vite frontend
FROM node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build


# Stage 2: Minimal Alpine + Nginx runtime
FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN apk upgrade --no-cache \
    && apk add --no-cache nginx gettext-envsubst \
    && mkdir -p /run/nginx /var/lib/nginx/tmp \
       /etc/nginx/templates /tmp/client_temp /tmp/proxy_temp \
       /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp \
    && chown -R nginx:nginx /run/nginx /var/lib/nginx \
       /etc/nginx /usr/share/nginx /tmp

COPY --from=builder --chown=nginx:nginx /app/dist/ /usr/share/nginx/html/
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx default.conf.template /etc/nginx/templates/default.conf.template
COPY --chown=nginx:nginx entrypoint.sh /entrypoint.sh

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["sh", "-c", "wget -q --header=\"Host: ${SERVER_NAME}\" -O /dev/null http://127.0.0.1:8080/"]

ENTRYPOINT ["sh", "/entrypoint.sh"]
