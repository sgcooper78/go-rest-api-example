# syntax=docker/dockerfile:1

# Comments are provided throughout this file to help you get started.
# If you need more help, visit the Dockerfile reference guide at
# https://docs.docker.com/go/dockerfile-reference/

# Want to help us make this template better? Share your feedback here: https://forms.gle/ybq9Krt8jtBL3iCk7

################################################################################
# Create a stage for building the application.
ARG GO_VERSION=1.23.0
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build
WORKDIR /src

# Download dependencies as a separate step to take advantage of Docker's caching.
# Leverage a cache mount to /go/pkg/mod/ to speed up subsequent builds.
# Leverage bind mounts to go.sum and go.mod to avoid having to copy them into
# the container.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,source=go.sum,target=go.sum \
    --mount=type=bind,source=go.mod,target=go.mod \
    go mod download -x && \
    go install github.com/air-verse/air@latest

# This is the architecture you're building for, which is passed in by the builder.
# Placing it here allows the previous steps to be cached across architectures.
ARG TARGETARCH

# Build the application.
# Leverage a cache mount to /go/pkg/mod/ to speed up subsequent builds.
# Leverage a bind mount to the current directory to avoid having to copy the
# source code into the container.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,target=. \
    CGO_ENABLED=0 GOARCH=$TARGETARCH go build -o /bin/server .

################################################################################
# Create a new stage for running the application with Air for development
FROM golang:${GO_VERSION} AS final

# Install any runtime dependencies that are needed to run your application.
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    && update-ca-certificates

# Create a non-privileged user that the app will run under.
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/home/appuser" \
    --shell "/bin/bash" \
    --uid "${UID}" \
    appuser

# Copy Air binary from the build stage
COPY --from=build /go/bin/air /bin/air

# Copy the source code to the container
WORKDIR /app
COPY . .

# Create tmp directory for Air and ensure proper permissions
RUN mkdir -p /app/tmp && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /home/appuser

# Expose the port that the application listens on.
EXPOSE 8080

USER appuser

# Set HOME environment variable explicitly
ENV HOME=/home/appuser

# What the container should run when it is started - use Air instead of the binary directly
ENTRYPOINT ["/bin/air"]
