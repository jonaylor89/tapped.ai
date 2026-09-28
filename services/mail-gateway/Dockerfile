FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npx haraka -i /app/haraka
COPY config /app/haraka/config
COPY plugins /app/haraka/plugins
EXPOSE 25
CMD ["/app/node_modules/.bin/haraka", "-c", "/app/haraka"]
