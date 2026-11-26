#!/bin/sh
set -eu

envsubst '${SERVER_NAME}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/http.d/default.conf

exec nginx -g 'daemon off;'
