# syntax=docker/dockerfile:1
#
# Contoso DotNet-Tools-TestApp on Ubuntu diagnostics-tools base
#
# Layers the linux-x64 publish output from tests/.build onto
# contoso/ubuntu-net-dotnet-tools-<version>:latest as the non-root
# contoso user (UID/GID 7777, home /app). Entry point is the apphost
# /app/DotNet-Tools-TestApp.
#
# Build example (run from repository root after the tools image and
# tests\.ps\.dotnet-tools-TestApp-build.ps1 succeed):
#
#   docker buildx build --no-cache --progress=plain \
#     -f tests/dockerfiles/ubuntu/Dockerfile \
#     --build-arg DOTNET_VERSION=10 \
#     -t contoso/ubuntu-net-dotnet-tools-testapp-10:latest \
#     tests/.build
#

ARG DOTNET_VERSION=10
ARG BASE_IMAGE=contoso/ubuntu-net-dotnet-tools-${DOTNET_VERSION}:latest

FROM ${BASE_IMAGE} AS final

# COPY/RUN require root; base ends as contoso.
USER root

# Publish output from tests/.build → /app (owned by contoso, same contract as
# COPY --chown=contoso:contoso [".empty", "/app/app-data"] on the base).
COPY --chown=contoso:contoso [".", "/app/"]

# Windows→Linux context copy may drop the execute bit on the ELF apphost.
RUN chmod 755 /app/DotNet-Tools-TestApp

WORKDIR /app
USER contoso

ENTRYPOINT ["/app/DotNet-Tools-TestApp"]
