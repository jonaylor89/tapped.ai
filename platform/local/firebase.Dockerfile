FROM node:24.10.0-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless curl \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g firebase-tools@14.20.0
WORKDIR /firebase
COPY firebase.json ./
COPY emulator-seed ./emulator-seed
EXPOSE 4000 9099
CMD ["firebase", "emulators:start", "--project", "demo-tapped", "--import", "emulator-seed"]
