# Build with the monorepo root as context: docker build -f services/event-crawler/Dockerfile .
FROM node:22.17.0-bookworm-slim AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.27.0 --activate
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/postgres-ingestion/package.json packages/postgres-ingestion/package.json
COPY services/event-crawler/package.json services/event-crawler/package.json
RUN pnpm install --filter node-webcrawler... --frozen-lockfile --ignore-scripts
COPY packages/postgres-ingestion/src packages/postgres-ingestion/src
COPY packages/postgres-ingestion/tsconfig.json packages/postgres-ingestion/tsconfig.json
COPY services/event-crawler/src services/event-crawler/src
COPY services/event-crawler/tsconfig.json services/event-crawler/tsconfig.json
RUN pnpm --filter @tapped/postgres-ingestion build && pnpm --filter node-webcrawler build

FROM node:22.17.0-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends chromium ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV CRAWLEE_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/postgres-ingestion ./packages/postgres-ingestion
COPY --from=builder /app/services/event-crawler/node_modules ./services/event-crawler/node_modules
COPY --from=builder /app/services/event-crawler/dist ./services/event-crawler/dist
COPY --from=builder /app/services/event-crawler/package.json ./services/event-crawler/package.json
RUN chown node:node /app/services/event-crawler
WORKDIR /app/services/event-crawler
USER node
CMD ["node", "dist/main.js"]
