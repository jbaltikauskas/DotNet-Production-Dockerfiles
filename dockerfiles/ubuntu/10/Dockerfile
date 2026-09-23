# syntax=docker/dockerfile:1
#
# Contoso .NET 10 ASP.NET production base (Ubuntu Noble)
#
# Note: "contoso" / "Contoso" is Microsoft's standard fictional enterprise placeholder
# (see https://learn.microsoft.com/style-guide/a-z-word-list-term-collections/term-collections/fictitious-names).
# Search-and-replace it with your real company name before publishing.
#
# Starts from Microsoft's official ASP.NET 10 Ubuntu Noble image and aligns it with the
# Alpine variant: production ASP.NET environment, ICU-based globalization (libicu74),
# server GC and heap limit, tzdata, CA certificates, and a non-root `contoso`
# user (UID/GID 7777) with home `/app`.
#
# Diagnostic CLIs (dotnet-debug, dotnet-gcdump, dotnet-trace) under `/app/dotnet-tools`.
# The tools come from the merged `dockerfiles/.dotnet-tools` folder, passed as an
# additional build context. The image is always tagged `:latest`.
#
# Build target:
#   final — runtime plus dockerfiles/.dotnet-tools
#
# Build example (run from repository root; syntax validated with BuildKit):
#
#   docker build -f dockerfiles/ubuntu/10/Dockerfile \
#     --target final \
#     --build-context dotnet-tools=dockerfiles/.dotnet-tools \
#     -t contoso/ubuntu-net-dotnet-tools-10:latest \
#     dockerfiles/ubuntu/10
#
# Result: same operational contract as the Alpine base—8080/8443, `/app` for the runtime
# user, `/app/.info/` snapshots (dotnet --info, os-release), and
# `/app/app-data`—on glibc Ubuntu instead of musl Alpine.
#
# Copy & Paste the following command to PS terminal to build the image localy:
#  docker buildx build --no-cache --progress=plain -f dockerfiles/ubuntu/10/Dockerfile --target final --build-context dotnet-tools=dockerfiles/.dotnet-tools -t contoso/ubuntu-net-dotnet-tools-10:latest dockerfiles/ubuntu/10

ARG DOTNET_VERSION=10.0

# === Runtime base (no SDK dependency) ===
FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble AS aspnet-base
ARG DOTNET_VERSION

ENV ASPNETCORE_ENVIRONMENT="Production"

LABEL contoso.Maintainer="Contoso, Inc." \
    contoso.BaseImage="ubuntu noble ${DOTNET_VERSION}" \
    contoso.Disclaimer="Contoso - Production Build" \
    org.opencontainers.image.description="Contoso DevOps Base Image for .NET" \
    org.opencontainers.image.licenses="MIT"

# Expose standard unprivileged container ports for web applications:
# - 8080: Default port for HTTP traffic
# - 8443: Default port for HTTPS traffic (if configured)
EXPOSE 8080 8443

# ASPNETCORE_URLS — Kestrel listens for HTTP on all interfaces, port 8080 (matches EXPOSE above).
# DOTNET_RUNNING_IN_CONTAINER — tells the runtime it is in a container (container-aware defaults where applicable).
# DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false — use ICU for culture-aware APIs; requires icu packages below.
# LANG/LC_ALL — locale for ICU-backed globalization (see dotnet-docker enable-globalization sample).
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_URLS=http://+:8080 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8

# DOTNET_gcServer=1 — server GC (throughput-oriented on multi-core hosts; typical for ASP.NET in containers).
# DOTNET_GCHeapHardLimitPercent — max managed GC heap as % of container memory (hex; 46 = 70%).
# Scales with the runtime memory limit; override at run time if needed (e.g. -e DOTNET_GCHeapHardLimitPercent=50).
ENV DOTNET_gcServer=1 \
    DOTNET_GCHeapHardLimitPercent=46

# Update package index, upgrade system packages, and install dependencies
# - libicu74       : ICU runtime for Ubuntu 24.04 Noble; pairs with DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false.
# - tzdata         : IANA time zone database for `TimeZoneInfo` and local-time conversions.
# - ca-certificates: system CA bundle; `update-ca-certificates` refreshes trust for TLS (HTTPS, NuGet, APIs).
# - adduser        : `adduser`/`addgroup` used below to create the non-root `contoso` account (Noble package).
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    libicu74 \
    tzdata \
    ca-certificates \
    adduser && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Define environment variables for the non-root application user and group.
# These ensure consistent IDs (7777) across the platform for permission matching and security.
ENV USERGROUP="contoso" \
    GID="7777" \
    USER="contoso" \
    UID="7777" \
    USER_HOME="/app"

# Create group contoso (gid 7777) and the non-root user with no password or login shell.
RUN addgroup --gid ${GID} ${USERGROUP} \
    && adduser \
        --disabled-password \
        --gecos "" \
        --home "${USER_HOME}" \
        --uid "${UID}" \
        --ingroup "${USERGROUP}" \
        "${USER}"

ARG INFO_DIR=/app/.info/

# create the empty .info directory (using .empty structure)
COPY --chown=contoso:contoso [".empty", "${INFO_DIR}"]

# Data (writable app state; same path as Alpine and Ubuntu Chiseled bases)
COPY --chown=contoso:contoso [".empty", "/app/app-data"]

# Runtime metadata snapshots (owned by contoso)
RUN <<EOT
  dotnet --info > ${INFO_DIR}dotnet.txt
  cat /etc/os-release > ${INFO_DIR}linux.txt
  chown -R ${USER}:${USERGROUP} ${INFO_DIR}
EOT

# APP_UID — ASP.NET Core container convention; matches contoso (7777).
ENV APP_UID=7777

# Switch to the non-root application user (reset in `final` after root COPY/RUN)
USER contoso

# === Final target: runtime plus dotnet-tools ===
FROM aspnet-base AS final

# COPY/RUN require root; aspnet-base ends as contoso. /app stays root-owned, so chmod must run as root.
USER root

# Merged diagnostic CLIs from dockerfiles/.dotnet-tools
# (dotnet-debug, dotnet-gcdump, dotnet-trace).
# Pass the folder as: --build-context dotnet-tools=dockerfiles/.dotnet-tools
#
# dotnet-trace
# dotnet-trace collect -o ./app-data/trace.nettrace --process-id 1 --duration 00:00:15
# dotnet-trace collect -o ./app-data/trace-cpu.nettrace --process-id 1 --duration 00:00:15 --profile dotnet-sampled-thread-time
# dotnet-trace collect -o ./app-data/trace-gc.nettrace --process-id 1 --duration 00:00:15 --profile gc-verbose
# dotnet-trace convert ./app-data/trace.nettrace --format Speedscope -o ./app-data/trace.speedscope.json
# dotnet-trace report ./app-data/trace.nettrace topN -n 10
#
# dotnet-gcdump (collect triggers a full GC)
# dotnet-gcdump collect -o ./app-data/heap.gcdump --process-id 1
# dotnet-gcdump collect -o ./app-data/heap-verbose.gcdump --process-id 1 --verbose --timeout 60
# dotnet-gcdump report ./app-data/heap.gcdump
# dotnet-gcdump report --process-id 1
# dotnet-gcdump ps
#
# dotnet-counters (collect and monitor exit after --duration)
# dotnet-counters collect -o ./app-data/counters.csv --format csv --process-id 1 --duration 00:00:15
# dotnet-counters collect -o ./app-data/counters.json --format json --process-id 1 --duration 00:00:15 System.Runtime
# dotnet-counters monitor --process-id 1 System.Runtime --refresh-interval 1 --duration 00:00:15
# dotnet-counters ps
#
# dotnet-debug (live attach; -c exit returns so docker exec does not stay open)
# dotnet-debug attach 1 -c clrstack -c exit
# dotnet-debug attach 1 -c "dumpheap -stat" -c exit
# dotnet-debug attach 1 -c clrthreads -c exit
# dotnet-debug attach 1 -c threadpool -c exit
# dotnet-debug attach 1 -c gcheapstat -c exit
COPY --chown=contoso:contoso --from=dotnet-tools / /app/dotnet-tools

# The merged folder ships DLLs only. These wrappers let PATH resolve the short names.
RUN <<'EOT'
for tool in dotnet-trace dotnet-gcdump dotnet-debug; do
  printf '#!/bin/sh\nexec dotnet /app/dotnet-tools/%s.dll "$@"\n' "$tool" > "/app/dotnet-tools/$tool"
done
EOT

# List copied tools with permissions (visible with: docker buildx build --progress=plain ...)
RUN echo "=== /app/dotnet-tools contents (permissions) ===" && \
    ls -laR /app/dotnet-tools && \
    echo "=== end /app/dotnet-tools ==="

# Prepend diagnostic tool directory for in-container troubleshooting
ENV PATH="/app/dotnet-tools:${PATH}"

# Ensure the application directory and all subdirectories are safely readable and executable,
# enforcing proper access controls for the non-root application user.
RUN chmod -R 755 /app

# Set the default working directory for the runtime container
WORKDIR /app

# Switch back to the non-root application user
USER contoso
