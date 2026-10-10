# Step 1: Build Stage
# Keep in sync with rust-toolchain.toml.
FROM rust:1.97.1-bookworm AS builder

# Create a new empty shell project
RUN USER=root cargo new --bin tapped-api-rs
WORKDIR /tapped-api-rs

# Copy over the manifests
COPY ./Cargo.toml ./Cargo.lock ./

# This build step will cache your dependencies
RUN cargo build --release
RUN rm src/*.rs

# Copy source code
COPY ./src ./src
COPY ./build.rs ./build.rs
COPY ./migrations ./migrations

# Build for release.
RUN touch src/main.rs && cargo build --release

# Step 2: Runtime Stage
FROM debian:bookworm-slim
LABEL io.tapped.datastore="postgres"

# Run as "app" user. The uid is fixed so the deploy can chown the mail volume and credentials.
RUN useradd -u 10001 -ms /bin/bash app && mkdir /data && chown app:app /data

# Install openssl
RUN apt-get -y update
RUN apt-get -y install openssl

# Install necessary runtime dependencies
RUN apt-get update && apt-get install -y libssl-dev ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy the build artifact from the build stage
COPY --from=builder /tapped-api-rs/target/release/tapped-api-rs /usr/local/bin/tapped-api-rs
COPY --from=builder /tapped-api-rs/target/release/mail_worker /usr/local/bin/mail_worker

# Set environment variables
ENV RUST_LOG=info

# Expose the port the app runs on
EXPOSE 3000

USER app

# Run the binary
CMD ["tapped-api-rs"]
