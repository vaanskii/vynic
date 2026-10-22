# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS build
ARG APP
WORKDIR /app/apps/${APP}
COPY apps/${APP}/package*.json ./
RUN npm ci
COPY apps/${APP}/ ./
# Preserve relative shared imports and manifest tooling in the monorepo layout.
COPY packages/website-client/ /app/packages/website-client/
# Platform regression/type checks import the real bespoke components.
COPY apps/vankisi-custom-web/ /app/apps/vankisi-custom-web/
RUN if [ "$APP" = "platform-web" ]; then npm ci --prefix /app/apps/vankisi-custom-web; fi
# Public compile-time configuration only. APIs stay on the browser's origin.
ARG VITE_COMING_SOON=false
ENV VITE_API_BASE_URL="" VITE_API_URL="/api" VITE_COMING_SOON=${VITE_COMING_SOON}
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.28-alpine AS runtime
USER root
# Serve exactly the reviewed artifact, without the base image's stock pages.
RUN rm -rf /usr/share/nginx/html/*
COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
ARG APP
COPY --from=build /app/apps/${APP}/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
