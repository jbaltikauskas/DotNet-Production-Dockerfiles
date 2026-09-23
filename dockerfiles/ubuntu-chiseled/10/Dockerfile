# syntax=docker/dockerfile:1
#
# Contoso .NET 10 ASP.NET production base (Ubuntu Chiseled, minimal rootfs)
#
# Note: "contoso" / "Contoso" is Microsoft's standard fictional enterprise placeholder
# (see https://learn.microsoft.com/style-guide/a-z-word-list-term-collections/term-collections/fictitious-names).
# Search-and-replace it with your real company name before publishing.
#
# Multi-stage build: copies the official ASP.NET 10 Noble Chiseled root filesystem, then
# uses Canonical Chisel (from a temporary SDK stage) to slice in only the extra packages
# needed—ICU libraries and tzdata zoneinfo—without a full package manager
# in the final image. The `contoso` user (7777) is added by editing passwd/group in the
# staged rootfs. The final stage is `FROM scratch`, so the image contains only that
# curated filesystem plus contoso labels and ASP.NET environment variables.
#
# Result: a very small, supply-chain-focused image with the same contoso runtime
# expectations (ports 8080/8443, globalization, GC tuning, APP_UID) as the full Alpine
# and Ubuntu images, but with a chiseled/distroless-style footprint. The non-root user
# `contoso` (UID/GID 7777) uses `/app` as its home and application root; downstream
# images should COPY published .NET build output into `/app` (e.g. `--chown=7777:7777`).
# Writable app state uses `/app/app-data`, same as the Alpine and Ubuntu bases.
#
# Background: https://github.com/dotnet/dotnet-docker/blob/main/documentation/ubuntu-chiseled.md
#
# Diagnostic CLIs (dotnet-debug, dotnet-gcdump, dotnet-trace) under `/app/dotnet-tools`.
# The tools come from the merged `dockerfiles/.dotnet-tools` folder, passed as an
# additional build context. The final image is scratch (no shell), so the tools
# listing runs in the chisel stage and is visible with `docker buildx build --progress=plain`.
# The image is always tagged `:latest`.
#
# Build target:
#   final — runtime plus dockerfiles/.dotnet-tools
#
# Copy & Paste the following command to PS terminal to build the image localy:
#  docker buildx build --no-cache --progress=plain -f dockerfiles/ubuntu-chiseled/10/Dockerfile --target final --build-context dotnet-tools=dockerfiles/.dotnet-tools -t contoso/ubuntu-chiseled-net-dotnet-tools-10:latest dockerfiles/ubuntu-chiseled/10

ARG ASPNET_CHISELED=mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
FROM ${ASPNET_CHISELED} AS aspnet-chiseled-base

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS chisel
ARG TARGETARCH
ARG CHISEL_VERSION=v1.4.0
ARG CHISEL_WRAPPER_VERSION=v1.2.0
ARG CHISEL_RELEASE=ubuntu-24.04

# Update package index and install build dependencies for the temporary sdk stage to fetch and run chisel:
# - ca-certificates: Required for secure TLS/HTTPS connections to download Chisel tools.
# - file           : Required by Chisel to inspect files and binaries while slicing them.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    file && \
    rm -rf /var/lib/apt/lists/*

# Map Docker BuildKit `TARGETARCH` (build platform) to the CPU suffix in Canonical's Chisel
# release tarball names (`chisel_*_linux_${c_arch}.tar.gz` on GitHub). Values match common
# `docker build --platform` targets; unknown architectures fail the build explicitly.
RUN case "$TARGETARCH" in \
    amd64) c_arch=amd64 ;; \
    arm64) c_arch=arm64 ;; \
    arm) c_arch=arm ;; \
    ppc64le) c_arch=ppc64le ;; \
    riscv64) c_arch=riscv64 ;; \
    s390x) c_arch=s390x ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH"; exit 1 ;; \
    esac \
    && curl -fSL -o /tmp/chisel.tgz \
    "https://github.com/canonical/chisel/releases/download/${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_${c_arch}.tar.gz" \
    && tar -xzf /tmp/chisel.tgz -C /usr/bin/ chisel \
    && rm /tmp/chisel.tgz \
    && curl -fSL -o /usr/bin/chisel-wrapper \
    "https://raw.githubusercontent.com/canonical/rocks-toolbox/${CHISEL_WRAPPER_VERSION}/chisel-wrapper" \
    && chmod 755 /usr/bin/chisel-wrapper

COPY --from=aspnet-chiseled-base / /rootfs/

# Chisel slices (see chisel-releases for ${CHISEL_RELEASE}): add only the listed paths into
# the staged rootfs—no full apt in the final image.
# - libicu74_libs         : ICU 74 shared libs for .NET when DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false.
# - tzdata-legacy_zoneinfo: legacy zoneinfo layout some stacks still resolve (companion to zoneinfo).
# - tzdata_zoneinfo       : IANA tz database (`/usr/share/zoneinfo`) for TimeZoneInfo / local time.
RUN chisel-wrapper --generate-dpkg-status /rootfs/var/lib/dpkg/status -- \
    --release ${CHISEL_RELEASE} --root /rootfs/ \
    libicu74_libs \
    tzdata-legacy_zoneinfo \
    tzdata_zoneinfo

# Staged filesystem root: paths like `app/...` below are the same tree as `/app/...` in the
# final image (aligned with Alpine/Ubuntu bases). Consumer Dockerfiles COPY publish output
# into `/app` (`--chown=7777:7777` here). `.info` and `app-data` are siblings under `app/`.
WORKDIR /rootfs

# create the app directories, create a group and user: contoso with gid/uid:7777 in the chiseled passwd
RUN mkdir -p app/.info app/app-data \
    && app_shell=$(awk -F: '/^app:/{print $7; exit}' etc/passwd) \
    && echo 'contoso:x:7777:' >> etc/group \
    && echo "contoso:x:7777:7777::/app:${app_shell:-/usr/sbin/nologin}" >> etc/passwd

# create the empty .info directory and app-data (using .empty structure)
COPY --chown=7777:7777 .empty app/.info/
COPY --chown=7777:7777 .empty app/app-data/

# capture system and runtime information snapshots directly into the application space
RUN <<EOT
  dotnet --info > app/.info/dotnet.txt
  cat /rootfs/etc/os-release > app/.info/linux.txt
  chown -R 7777:7777 app/.info
EOT

# === Runtime rootfs (labels and environment; tools are added in `final`) ===
FROM scratch AS runtime-base
COPY --from=chisel /rootfs /

LABEL contoso.Maintainer="Contoso, Inc." \
    contoso.BaseImage="ubuntu noble chiseled" \
    contoso.Disclaimer="Contoso - Production Build" \
    org.opencontainers.image.description="Contoso DevOps Base Image for .NET (Ubuntu Chiseled + Chisel)" \
    org.opencontainers.image.licenses="MIT"

# Expose standard unprivileged container ports for web applications:
# - 8080: Default port for HTTP traffic
# - 8443: Default port for HTTPS traffic (if configured)
EXPOSE 8080 8443

# ASPNETCORE_ENVIRONMENT — run the app with Production config and middleware defaults.
# ASPNETCORE_HTTP_PORTS — port Kestrel uses when binding via the default HTTP endpoint (8080; aligns with EXPOSE).
# ASPNETCORE_URLS — explicit listener URL: HTTP on all interfaces, port 8080 (same contract as Alpine/Ubuntu bases).
# DOTNET_RUNNING_IN_CONTAINER — tells the runtime it is in a container (container-aware defaults where applicable).
# DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false — use ICU for culture-aware APIs; requires Chisel ICU slices in this image.
# LANG/LC_ALL — locale for ICU-backed globalization (aligned with Alpine/Ubuntu bases).
# DOTNET_gcServer=1 — server GC (throughput-oriented on multi-core hosts; typical for ASP.NET in containers).
# DOTNET_GCHeapHardLimitPercent — max managed GC heap as % of container memory (hex; 46 = 70%).
# Scales with the runtime memory limit; override at run time if needed (e.g. -e DOTNET_GCHeapHardLimitPercent=50).
# APP_UID — non-root application user id expected by ASP.NET Core images (matches contoso UID in the rootfs).
ENV ASPNETCORE_ENVIRONMENT="Production" \
    ASPNETCORE_HTTP_PORTS="8080" \
    ASPNETCORE_URLS="http://+:8080" \
    DOTNET_RUNNING_IN_CONTAINER="true" \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT="false" \
    LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    DOTNET_gcServer="1" \
    DOTNET_GCHeapHardLimitPercent="46" \
    APP_UID="7777"

CMD ["--info"]

# === Tool permissions (scratch has no shell, so chown, chmod, and the listing run here) ===
FROM chisel AS dotnet-tools-listing

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
COPY --from=dotnet-tools / /rootfs/app/dotnet-tools

# Permissions for the whole staged `/app` tree (dotnet-tools + .info + app-data).
# chmod/chown MUST happen in this chisel-based stage: the published `final`
# image is FROM scratch and has no shell, so no later `RUN` can adjust permissions.
RUN chown -R 7777:7777 /rootfs/app && \
    chmod -R 755 /rootfs/app && \
    echo "=== /app/dotnet-tools contents (permissions) ===" && \
    ls -laR /rootfs/app/dotnet-tools && \
    echo "=== end /app/dotnet-tools ==="

FROM runtime-base AS final

# Merged diagnostic CLIs from dockerfiles/.dotnet-tools
# (dotnet-debug, dotnet-gcdump, dotnet-trace).
# Pass the folder as: --build-context dotnet-tools=dockerfiles/.dotnet-tools
# Permissions (755, uid/gid 7777) were already applied in the dotnet-tools-listing stage —
# scratch has no shell, so a `RUN chmod` here would fail with `/bin/sh: no such file or directory`.
COPY --from=dotnet-tools-listing /rootfs/app/dotnet-tools /app/dotnet-tools

# Prepend diagnostic tool directory for in-container troubleshooting
ENV PATH="/app/dotnet-tools:${PATH}"

# Set the default working directory for the runtime container (metadata only; no shell needed)
WORKDIR /app

# Switch back to the non-root application user
USER contoso
