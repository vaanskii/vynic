# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS build
ARG APP
WORKDIR /app
COPY apps/${APP}/package*.json ./
RUN npm ci
COPY apps/${APP}/ ./
# Public compile-time configuration only. APIs stay on the browser's origin.
ARG VITE_COMING_SOON=false
ENV VITE_API_BASE_URL="" VITE_API_URL="/api" VITE_COMING_SOON=${VITE_COMING_SOON}
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.28-alpine AS runtime
COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
