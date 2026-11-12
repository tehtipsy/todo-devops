# syntax=docker/dockerfile:1

# Frontend image: Nginx serving the static UI and reverse-proxying /api/ to the
# backend. The UI source comes from the named build context `app`:
#
#   docker build --build-context app=../todo-app -t todo-frontend docker/frontend

ARG NGINX_VERSION=1.29

# The unprivileged variant runs as UID 101 and listens on 8080, so the
# container never needs root, not even to bind its port.
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine

# Where /api/ is proxied to. Rendered into the config at container start by
# the image's envsubst entrypoint (only these variables are substituted).
ENV BACKEND_HOST=backend \
    BACKEND_PORT=3000

COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=app frontend/public/ /usr/share/nginx/html/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/nginx-health"]
