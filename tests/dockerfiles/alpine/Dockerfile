# syntax=docker/dockerfile:1
#
# Contoso DotNet-Tools-TestApp on Alpine diagnostics-tools base
#
# Layers the linux-x64 publish output from tests/.build onto
# contoso/alpine-net-dotnet-tools-<version>:latest as the non-root
# contoso user (UID/GID 7777, home /app).
#
# The copied apphost is a glibc ELF (interpreter /lib64/ld-linux-x86-64.so.2).
# Alpine is musl, so exec of that file returns "no such file or directory"
# even when /app/DotNet-Tools-TestApp is present. Start the portable DLL
# with the musl `dotnet` host already in the base image. Ubuntu and
# Ubuntu Chiseled keep the apphost entry point.
#
# Build example (run from repository root after the tools image and
# tests\.ps\.dotnet-tools-TestApp-build.ps1 succeed):
#
#   docker buildx build --no-cache --progress=plain \
#     -f tests/dockerfiles/alpine/Dockerfile \
#     --build-arg DOTNET_VERSION=10 \
#     -t contoso/alpine-net-dotnet-tools-testapp-10:latest \
#     tests/.build
#

ARG DOTNET_VERSION=10
ARG BASE_IMAGE=contoso/alpine-net-dotnet-tools-${DOTNET_VERSION}:latest

FROM ${BASE_IMAGE} AS final

# COPY/RUN require root; base ends as contoso.
USER root

# Publish output from tests/.build → /app (owned by contoso, same contract as
# COPY --chown=contoso:contoso [".empty", "/app/app-data"] on the base).
COPY --chown=contoso:contoso [".", "/app/"]

WORKDIR /app
USER contoso

# dotnet is PID 1 and hosts DotNet-Tools-TestApp.dll in-process.
ENTRYPOINT ["dotnet", "/app/DotNet-Tools-TestApp.dll"]
