# syntax=docker/dockerfile:1
#
# Contoso DotNet-Tools-TestApp on Ubuntu Chiseled diagnostics-tools base
#
# Layers the linux-x64 publish output from tests/.build onto
# contoso/ubuntu-chiseled-net-dotnet-tools-<version>:latest as the
# non-root contoso user (UID/GID 7777, home /app). Entry point is the
# apphost /app/DotNet-Tools-TestApp.
#
# The chiseled base is scratch (no shell), so execute-bit and ownership
# are applied in a short busybox stage before the final COPY.
#
# Build example (run from repository root after the tools image and
# tests\.ps\.dotnet-tools-TestApp-build.ps1 succeed):
#
#   docker buildx build --no-cache --progress=plain \
#     -f tests/dockerfiles/ubuntu-chiseled/Dockerfile \
#     --build-arg DOTNET_VERSION=10 \
#     -t contoso/ubuntu-chiseled-net-dotnet-tools-testapp-10:latest \
#     tests/.build
#

ARG DOTNET_VERSION=10
ARG BASE_IMAGE=contoso/ubuntu-chiseled-net-dotnet-tools-${DOTNET_VERSION}:latest

# Scratch has no shell — set permissions here, then copy into final.
FROM busybox:1.36 AS app-perms
COPY [".", "/app/"]
RUN chmod 755 /app/DotNet-Tools-TestApp && chown -R 7777:7777 /app

FROM ${BASE_IMAGE} AS final

# Publish output from tests/.build → /app (contoso UID/GID 7777; same
# ownership contract as the Alpine/Ubuntu bases and the chiseled rootfs).
COPY --from=app-perms --chown=contoso:contoso ["/app/", "/app/"]

WORKDIR /app
USER contoso

ENTRYPOINT ["/app/DotNet-Tools-TestApp"]
