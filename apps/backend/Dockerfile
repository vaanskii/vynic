# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY apps/backend/package*.json ./
COPY apps/backend/prisma ./prisma
# Generate from the schema; no application .env or database connection is needed.
RUN npm ci
COPY apps/backend/tsconfig*.json apps/backend/nest-cli.json ./
COPY apps/backend/src ./src
COPY apps/backend/scripts/create-platform-admin.ts apps/backend/scripts/seed-docker-local.ts apps/backend/scripts/studio-docker-local.ts apps/backend/scripts/reset-docker-customers.ts ./scripts/
RUN npm run build && find dist -name '*.map' -delete && find dist -name '*.d.ts' -delete
RUN npm prune --omit=dev && npm cache clean --force

FROM node:22-bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build /app/package*.json ./
COPY --from=build /app/prisma ./prisma
RUN mkdir -p /var/lib/vynic/media && chown node:node /var/lib/vynic/media
USER node
EXPOSE 3000
# Deliberately bypass npm's prestart:prod migration hook. One job owns migrations.
CMD ["node", "dist/src/main.js"]
