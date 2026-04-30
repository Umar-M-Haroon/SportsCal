# ================================
# Build stage
# ================================
FROM swift:6.0-jammy AS build

WORKDIR /build

# Copy the shared model package first (for layer caching)
COPY SportsCalModel/ SportsCalModel/

# Copy server package files for dependency resolution
COPY SportsCalAPI/SportsCalServer/Package.swift SportsCalAPI/SportsCalServer/Package.resolved SportsCalAPI/SportsCalServer/

# Resolve dependencies (cached unless Package.swift changes)
WORKDIR /build/SportsCalAPI/SportsCalServer
RUN swift package resolve

# Copy server source code
COPY SportsCalAPI/SportsCalServer/Sources/ Sources/
COPY SportsCalAPI/SportsCalServer/Tests/ Tests/

# Build in release mode
RUN swift build -c release

# ================================
# Runtime stage
# ================================
FROM swift:6.0-jammy-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app

# Copy built binary
COPY --from=build /build/SportsCalAPI/SportsCalServer/.build/release/Run .

# Copy static files (admin dashboard)
COPY SportsCalAPI/SportsCalServer/Public/ Public/

# Pre-create the PBP data dir so the named volume inherits vapor ownership when
# Docker initializes a fresh volume from the image. Without this, the volume
# mountpoint is created by the daemon as root:root and the vapor user can't
# write the SQLite archive.
RUN mkdir -p /app/pbp_data

# Set ownership
RUN chown -R vapor:vapor /app

USER vapor

EXPOSE 8080

ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
