# syntax=docker/dockerfile:1

# Backend image for the TODO API.
#
# The application source lives in a separate repository, so it is supplied as
# the named build context `app` instead of the main context:
#
#   docker build --build-context app=../todo-app -t todo-backend docker/backend
#
# Stages:
#   prod-deps  production node_modules only
#   test       lint + unit/API tests (docker build --target test ...)
#   runtime    final image (default target)

ARG NODE_VERSION=24

FROM node:${NODE_VERSION}-alpine AS base
WORKDIR /app

# --- production dependencies -------------------------------------------------
# Only the manifests are copied before `npm ci`, so this layer is rebuilt when
# dependencies change and reused when only source code does.
FROM base AS prod-deps
COPY --from=app backend/package.json backend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# --- lint and tests ----------------------------------------------------------
FROM base AS test
COPY --from=app backend/package.json backend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci
COPY --from=app backend/eslint.config.js backend/jest.config.js ./
COPY --from=app backend/docs ./docs
COPY --from=app backend/src ./src
COPY --from=app backend/tests ./tests
RUN npm run lint && npm test

# --- runtime -----------------------------------------------------------------
FROM base AS runtime

ENV NODE_ENV=production \
    PORT=3000

# tini runs as PID 1: it forwards SIGTERM to Node (graceful shutdown) and reaps zombies.
RUN apk add --no-cache tini

# Files stay owned by root and are only readable by the unprivileged runtime
# user, so a compromised process cannot modify the application code.
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=app backend/package.json ./
COPY --from=app backend/docs ./docs
COPY --from=app backend/src ./src

# The image's `node` user, by numeric UID:GID - a name may not resolve on the
# host, and a numeric user lets Kubernetes verify runAsNonRoot from the image.
USER 1000:1000
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:' + process.env.PORT + '/health/live').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/server.js"]
