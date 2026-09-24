# DotNet-Production-Dockerfiles

Starting every application Dockerfile from Microsoft's runtime the way the samples do — `FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base`, then `USER app`, `WORKDIR /app`, `EXPOSE 8080` and way more — does not scale when an enterprise maintains many images. Split production into two steps. The first step takes the Microsoft image and adds the dependencies, settings, and hardening the company requires, including .NET diagnostic tools for troubleshooting; that build produces the company's base images, and applications later choose among all three (Alpine, Ubuntu Noble, and Ubuntu Chiseled). The second step only copies the company's published build artifacts onto the chosen base.

This repository provides enterprise, production-ready Dockerfile examples for .NET 10 base images, with **Alpine Linux as the primary, recommended choice**:

- **Alpine Linux (Primary Choice)**: [`dockerfiles/alpine/10/Dockerfile`](dockerfiles/alpine/10/Dockerfile) — Minimal footprint (~45 MB), musl libc, full ICU globalization pre-configured, shell/apk for easy debugging, and diagnostic CLIs under `/app/dotnet-tools`.
- **Ubuntu Noble (24.04 LTS, Secondary Choice)**: [`dockerfiles/ubuntu/10/Dockerfile`](dockerfiles/ubuntu/10/Dockerfile) — Full glibc runtime, shell access, package manager (`apt`), and broad native library compatibility.
- **Ubuntu Chiseled (Last-Resort Distroless Alternative)**: [`dockerfiles/ubuntu-chiseled/10/Dockerfile`](dockerfiles/ubuntu-chiseled/10/Dockerfile) — Ultra-minimal distroless runtime, zero shell, no package manager, and minimal CVE attack surface. **Trade-off:** runs as non-root by default (`APP_UID=7777`) with no shell of any kind (no `bash`, `sh`, or `dash`) and no `apt`/`apk` — verified in our [Chiseled Dockerfile](dockerfiles/ubuntu-chiseled/10/Dockerfile). That lockdown is exactly what makes it secure, but it also makes it **extremely difficult to troubleshoot .NET memory leaks, GC pressure, thread starvation, or other runtime issues in Dev/QA** — no `docker exec` into a shell. The diagnostic CLIs are present under `/app/dotnet-tools`, but with no shell you still need an ephemeral debug sidecar or a rebuild against a full-shell image to run them. Only justify this option when the security posture demands it — for example, a hardened login/authentication microservice, a token issuer, or a workload under a strict distroless compliance mandate. Default services should use [Alpine](#alpine-linux-primary-choice) (primary) or [Ubuntu Noble](#ubuntu-noble-secondary-choice) (secondary) instead.

> **Note:** This repository is an example and reference repository. Do not edit or build directly within this repository for your organization.

### Turnkey Adoption: Copy & Replace

> **What is `contoso`?** `Contoso` (lowercase `contoso` in identifiers) is Microsoft's standard, universally-recognized fictional enterprise placeholder — the same one used across Microsoft Learn, Azure, .NET, and Microsoft 365 documentation for sample code, tenants, users, and organizations. See [Microsoft 365 for enterprise for the Contoso Corporation](https://learn.microsoft.com/en-us/microsoft-365/enterprise/contoso-case-study?view=o365-worldwide). We use it here so every reference is obviously a placeholder that you own the responsibility to replace with your real organization's name.

These Dockerfiles are fully production-ready out of the box. Adopting them in your client or organizational projects requires just two steps:

1. **Copy & Paste**: Copy the desired Dockerfile ([Alpine](dockerfiles/alpine/10/Dockerfile), [Ubuntu](dockerfiles/ubuntu/10/Dockerfile), or [Ubuntu Chiseled](dockerfiles/ubuntu-chiseled/10/Dockerfile)) into your own project repository.
2. **Search & Replace**: Open the Dockerfile in your text editor and do a case-sensitive find-and-replace:
   - Replace `contoso` (lowercase) with your organization's lowercase identifier (e.g., `acme`) — used in image tags, LABEL keys, and the non-root Linux user/group name (Docker image names and Linux user names must be lowercase).
   - Replace `Contoso` (title case) with your organization's display name (e.g., `Acme, Inc.`) — used in maintainer strings, human-readable descriptions, and comments.

That is it. That single search-and-replace updates:
- Image labels and metadata (`contoso.Maintainer`, `contoso.Disclaimer`, `Contoso, Inc.`, etc.)
- Non-root user and group configuration (`USERGROUP="contoso"`, `USER="contoso"`, or `/etc/passwd` entries)
- Image tags (`contoso/alpine-net-dotnet-tools-10:latest`) and maintainer comments

---

Microsoft's app Dockerfile samples typically use a multi-stage build that starts the runtime stage straight from an official image:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER app
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["MyApp/MyApp.csproj", "MyApp/"]
RUN dotnet restore "./MyApp/MyApp.csproj"
COPY . .
WORKDIR "/src/MyApp"
RUN dotnet build "./MyApp.csproj" -c $BUILD_CONFIGURATION -o /app/build

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./MyApp.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

That skips the layer most organizations need first: a **company base image** built on top of Microsoft's runtime (hardening, users, env defaults, CA certs, diagnostic CLIs). This repo documents how to choose among Microsoft's .NET 10 bases (Alpine, Ubuntu Noble, Ubuntu Chiseled) and provides the wrapper Dockerfiles that produce that company base — for example `dockerfiles/alpine/10/Dockerfile`. Application Dockerfiles should then look like this instead:

```dockerfile
FROM contoso/alpine-net-dotnet-tools-10:latest AS base

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
# ... (build and publish stages remain the same, using Microsoft's SDK) ...
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["MyApp/MyApp.csproj", "MyApp/"]
RUN dotnet restore "./MyApp/MyApp.csproj"
COPY . .
WORKDIR "/src/MyApp"
RUN dotnet publish "./MyApp.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

Treat the contents as guidelines, not a mandate. Align with your team's standards, registry policy, and risk posture.

---

## Who should read what

**Application developers.** Your main decision is between Alpine (our recommended primary base), Ubuntu Noble (secondary), and Ubuntu Chiseled (last resort). The short answer for new .NET 10 ASP.NET services is **Alpine** (`alpine-net-dotnet-tools-10`): it delivers the ideal combination of minimal footprint (~45 MB compressed), low CVE attack surface, fast cold starts, full ICU globalization configured out of the box in our wrapper, and a built-in shell (`sh`/`apk`) for break-glass diagnostics. If Alpine's musl libc rules out a required native dependency, move to full Ubuntu Noble (`ubuntu-net-dotnet-tools-10`) as the secondary choice — glibc, `apt`, and bash preserved. Only reach for Ubuntu Chiseled (`noble-chiseled` / `noble-chiseled-extra`) as a last resort when policy strictly mandates a zero-shell distroless profile on glibc. See [musl vs glibc in practice](#musl-vs-glibc-in-practice).

**Platform and DevOps.** Alpine is the default base for CI throughput and registry storage efficiency. Ubuntu Noble is the secondary base for workloads that need glibc or `apt`. Catalog of images is in [The images at a glance](#the-images-at-a-glance) and [Image size comparison](#image-size-comparison). Every image copies a merged tools folder from [Diagnostic tools build](#diagnostic-tools-build) rather than running `dotnet tool install` inside the image. Build and CI patterns are below; published images live in [Published images (GHCR)](#published-images-ghcr).

**Security and compliance.** Alpine provides an exceptionally small package footprint with minimal CVE attack surface while retaining shell access for observability. Ubuntu Noble carries a broader package set but delivers standard glibc runtime compatibility. Ubuntu Chiseled is the strictest lockdown option: it removes the shell and package manager entirely at the expense of requiring ephemeral sidecars for interactive debugging. Every Contoso image includes `dotnet-debug`, `dotnet-gcdump`, and `dotnet-trace` under `/app/dotnet-tools` and is tagged `:latest`. See [Diagnostic CLIs](#diagnostic-clis). Patching follows whatever upstream Microsoft and distro lifecycles you pin to. This README does not replace your org's image allow-list or tagging policy.

---

## The images at a glance

```bash
# Microsoft official .NET 10 — Alpine (Primary Choice)
mcr.microsoft.com/dotnet/aspnet:10.0-alpine
mcr.microsoft.com/dotnet/aspnet:10.0-alpine3.21

# Microsoft official .NET 10 — Ubuntu Noble (Secondary Choice)
mcr.microsoft.com/dotnet/aspnet:10.0-noble

# Microsoft official .NET 10 — Ubuntu Chiseled (Last-Resort Distroless Alternative)
mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled        # minimal Ubuntu, distroless-style
mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra  # chiseled + ICU/tzdata
```

## Image size comparison

Approximate sizes for the ASP.NET runtime image on .NET 10. Sizes shift with each servicing release; for current numbers see Microsoft's [sample image size report](https://github.com/dotnet/dotnet-docker/blob/main/documentation/sample-image-size-report.md).


| Image                            | Compressed | Uncompressed |
| -------------------------------- | ---------- | ------------ |
| `10.0-alpine` (Primary Choice)   | ~45 MB     | ~115 MB      |
| `10.0-alpine-composite`          | ~38 MB     | ~98 MB       |
| `10.0-noble` (Secondary Choice)  | ~90 MB     | ~220 MB      |
| `10.0-noble-chiseled` (Last)     | ~40 MB     | ~105 MB      |


Alpine is our primary choice (~45 MB compressed) because it combines a minimal footprint and ultra-low CVE surface with operational ergonomics: you retain a lightweight shell (`sh`) and package manager (`apk`) for debugging when needed, with full ICU globalization pre-configured in our wrapper. Ubuntu Noble is the secondary choice when glibc, `apt`, or bash are required, at the cost of the ~220 MB uncompressed footprint. Ubuntu Chiseled sits within a few megabytes of Alpine on size but is reserved as a last-resort distroless option when policy strictly forbids a shell or package manager in the runtime image.

---

## Alpine Linux (Primary Choice)

Alpine Linux is the **primary recommended base image** in this repository. It delivers an ultra-compact footprint (~45 MB compressed), rapid container startup times, minimal CVE attack surface, and essential operational tooling (`sh` and `apk`) for runtime inspection and break-glass debugging.

While stock Alpine images often require manual setup for internationalization and native dependencies, **our `alpine-net-dotnet-tools-10` wrapper addresses these concerns out of the box** by pre-installing `icu-data-full`, `icu-libs`, and `tzdata`, and setting `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`.

**Strengths**

- **Primary production recommendation**: Best overall balance of minimal size, security hardening, and operational observability.
- **Ultra-compact size**: ~45 MB compressed (~115 MB uncompressed) allows rapid image pulls, faster autoscaling pod launches, and reduced registry storage costs.
- **Minimal attack surface**: Ships only the minimal musl and Alpine package set, significantly reducing scanner CVE noise and maintenance overhead compared to full distributions.
- **Operational ergonomics**: Unlike distroless images, Alpine includes a lightweight shell (`/bin/sh`) and `apk`, allowing developers to inspect containers or execute diagnostics during incidents.
- **Turnkey ICU globalization**: Our wrapper pre-bakes full internationalization data and timezone support (`icu-data-full`, `icu-libs`, `tzdata`).
- **Diagnostic tool support**: `dotnet-trace`, `dotnet-gcdump`, and `dotnet-debug` are copied to `/app/dotnet-tools` and placed on `PATH`.
- **Cost and bandwidth savings**: Quicker CI throughput and reduced egress costs across large deployment fleets.

**Considerations**

- Uses `musl libc` instead of `glibc`. The vast majority of pure .NET applications and standard NuGet packages run identically on musl.
- Native C/C++ dependencies: Third-party native packages (such as SkiaSharp, legacy `libgdiplus`, or specialized PDF engines) may require additional `apk` packages or only supply glibc binaries.
- Self-contained single-binary publish requires specifying `--runtime linux-musl-x64` (or `linux-musl-arm64`).
- If an application has an unavoidable dependency on a proprietary glibc-only binary that cannot be satisfied in Alpine, fall back to our Ubuntu Noble wrapper (secondary choice) or, as a last resort, the Ubuntu Chiseled wrapper.

---

## Ubuntu Noble (Secondary Choice)

`mcr.microsoft.com/dotnet/*:10.0-noble` is a conventional Linux container with glibc, bash shell, `apt`, and standard Ubuntu packages. It serves as our **secondary choice** for workloads that need broad native package compatibility, `apt` at build time, or complex third-party tools that Alpine's musl runtime cannot satisfy.

**Strengths**

- Full glibc runtime — maximum compatibility with legacy NuGet packages or third-party native `.so` binaries.
- Standard `apt` package manager and bash shell available for complex runtime setups or debugging.
- Out-of-the-box ICU globalization.
- Seamless fit for SkiaSharp, ImageSharp, OpenSSL-heavy workloads, and any "install another deb" scenario.
- Standard Canonical LTS support through April 2029.

**Limitations**

- Noticeably larger disk footprint (~90 MB compressed, ~220 MB uncompressed) than Alpine and Chiseled. See [Image size comparison](#image-size-comparison).
- Broader patch and CVE attack surface due to the large set of installed utility packages.
- Slower container cold starts and higher bandwidth consumption at scale.

When to choose: Start with **Alpine** for new and existing standard services. Move to Ubuntu Noble when you hit musl native library limitations or need `apt` and full OS utilities. Reserve Ubuntu Chiseled as a last-resort option only when a strict distroless mandate applies.

---

## Ubuntu Chiseled (Last-Resort Distroless Alternative)

Ubuntu Chiseled (`*-noble-chiseled`, `*-noble-chiseled-extra`) is a distroless-style **last-resort alternative** built by Canonical in partnership with Microsoft using the Chisel tool. It contains only the slice of Ubuntu .NET strictly requires: no shell, no package manager, non-root by default, and a minimal package count. See the [official overview](https://github.com/dotnet/dotnet-docker/blob/main/documentation/ubuntu-chiseled.md).

There is no Chiseled SDK image. You publish with `mcr.microsoft.com/dotnet/sdk:*-noble` and run on a Chiseled runtime tag.

Reach for Chiseled only after Alpine and Ubuntu Noble have been ruled out — for example, when an organizational policy specifically mandates zero shell access or distroless containers on glibc. The strict lockdown comes with a substantial operational cost: no interactive debugging, no runtime package installs, and reliance on ephemeral debug pods or sidecars for any break-glass work.

### Security-critical services requiring zero-shell policy

When organizational policy mandates zero shell access or distroless containers on glibc, Ubuntu Chiseled fits that requirement. If an attacker reaches an application-level vulnerability, the runtime image provides no shell, no `apt`, and no operating system utilities to pivot with. The small package set keeps scanner noise low.

Choose Chiseled when your operational model does not require an in-container shell and break-glass debugging is handled via debug sidecars, ephemeral pods, or platform telemetry — and after confirming that Alpine's minimal footprint plus non-root user does not already satisfy the same threat model.

**Strengths**

- Small compressed and uncompressed size (~40 MB compressed) on glibc.
- Minimal package set — only what Chisel slices in.
- Zero shell and no package manager in runtime for maximum lockdown.
- `noble-chiseled-extra` provides ICU and timezone data on glibc.
- Non-root by default (`APP_UID=7777` in our wrapper).
- Same glibc lineage as Ubuntu, avoiding musl compatibility issues for glibc native binaries.

**Limitations**

- No shell: `docker exec` into a shell will not work. Interactive troubleshooting requires sidecars or ephemeral debug pods.
- No package manager: Cannot install troubleshooting utilities at runtime; any change requires rebuilding or modifying Chisel slices.
- Variant selection: Must choose between base and `-extra` (for ICU/tzdata).
- Build stage requires the full Ubuntu SDK image.
- Highest operational overhead of the three options — reserve for last-resort scenarios.

---

## Side-by-side comparison


| Factor                       | Alpine (Primary Choice)                  | Ubuntu Noble (Secondary Choice) | Ubuntu Chiseled (Last Resort) |
| ---------------------------- | ---------------------------------------- | ------------------------------- | ----------------------------- |
| Role in repository           | **Primary recommended standard**         | Secondary choice                | Last-resort distroless        |
| Base C library               | musl                                     | glibc                           | glibc                         |
| ASP.NET runtime image size   | ~115 MB (~45 MB compressed)              | ~220 MB (~90 MB)                | ~105 MB (~40 MB compressed)   |
| Native library compatibility | Good (pure .NET + musl packages)         | Full (glibc + apt)              | Excellent (glibc)             |
| NuGet native dependencies    | Standard packages supported              | Full support                    | Full support                  |
| Globalization / ICU          | **Full ICU pre-configured in wrapper**   | Out of box                      | Via `-extra` tag              |
| Shell access for debugging   | **Yes (`/bin/sh`)**                      | Yes (`/bin/bash`)               | No (ephemeral pods only)      |
| Package manager              | `apk`                                    | `apt`                           | None                          |
| Typical scanner CVE noise    | Very low                                 | Higher                          | Very low                      |
| Non-root in our wrapper      | Yes (`contoso` UID 7777)                 | Yes (`contoso` 7777)            | Yes (`contoso` 7777)          |
| SkiaSharp / System.Drawing   | Needs extra apk libs                     | Works                           | Works                         |
| Self-contained publish       | `linux-musl-x64`                         | `linux-x64`                     | `linux-x64`                   |
| Kubernetes pod startup       | Fast                                     | Medium                          | Fast                          |
| Distro lifecycle             | Rolling (Alpine 3.21)                    | 2029 (Ubuntu 24.04 LTS)         | 2029 (Ubuntu 24.04 LTS)       |
| Best fit                     | **Modern microservices & APIs (Default)**| Heavy native C/C++ deps         | Zero-shell security policy    |


CVE counts on fresh builds are roughly comparable between Alpine and Chiseled because both ship a minimal package set. Full Noble carries more components, so scanners typically flag more findings — most of them in OS utilities the app does not actually use.

---

## musl vs glibc in practice

When deploying on Alpine, standard ASP.NET Core applications run without issues. The potential hurdles developers occasionally hit in raw Alpine images relate to missing native libraries or unconfigured globalization:

```text
# Native lib not found
System.DllNotFoundException: Unable to load shared library 'libgdiplus'

# Globalization mode wrong for the workload
System.Globalization.CultureNotFoundException:
Only the invariant culture is supported in globalization-invariant mode.
```

How these are addressed:

1. **Globalization is pre-solved in our wrapper**: Our `alpine-net-dotnet-tools-10` Dockerfile already installs `icu-data-full`, `icu-libs`, and `tzdata`, and sets `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`. You will not encounter `CultureNotFoundException` out of the box.
2. **Missing musl-compatible native libs**: If your application uses a library like `System.Drawing.Common`, install the appropriate Alpine package via `apk add` (e.g. `apk add --no-cache libgdiplus`).
3. **Proprietary or glibc-only binaries**: If a third-party NuGet package ships precompiled native binaries that only support glibc and cannot run under musl, fall back first to full `ubuntu-net-dotnet-tools-10` (secondary choice). Reserve `ubuntu-chiseled-extra` as a last-resort escape hatch for strict distroless policies.

---

## Choosing a base image

```text
Default choice for modern ASP.NET Core APIs and microservices
  -> alpine-net-dotnet-tools-10 — Primary standard: ~45 MB footprint, minimal CVE surface, shell included, full ICU pre-configured

Needs SkiaSharp, ImageSharp, System.Drawing, or proprietary glibc native libraries
  -> ubuntu-net-dotnet-tools-10 — Secondary choice: full glibc, apt, and bash when musl native libraries are unavailable

Zero-shell security policy or strict distroless compliance (only after Alpine and Ubuntu Noble are ruled out)
  -> ubuntu-chiseled-net-dotnet-tools-10 — Last-resort distroless glibc runtime, zero shell, no package manager

In-image diagnostic CLIs (dotnet-trace, dotnet-gcdump, dotnet-debug)
  -> included on every image under /app/dotnet-tools and tagged :latest

Routine break-glass debugging + ultra-compact image footprint
  -> alpine-net-dotnet-tools-10 — includes sh and apk without the 220 MB footprint of full Ubuntu

Self-contained single-binary publish
  -> alpine-net-dotnet-tools-10 with linux-musl-x64 (or ubuntu-net-dotnet-tools-10 with linux-x64)
```

Rough rule of thumb across teams:

- **Default to Alpine (`alpine-net-dotnet-tools-10`)**: This is the recommended primary choice for modern .NET 10 microservices, APIs, and background workers. It provides the optimal balance of tiny image footprint (~45 MB compressed), rapid startup, and minimal attack surface, while retaining `sh` and `apk` for operational inspection and baking in full ICU globalization.
- **Secondary: Full Ubuntu (`ubuntu-net-dotnet-tools-10`)**: Move to Ubuntu Noble when your workload requires `apt`, complex native `.so` binaries without musl ports, bash for interactive debugging, or when mirroring a local Ubuntu desktop environment.
- **Last resort: Ubuntu Chiseled (`ubuntu-chiseled-net-dotnet-tools-10`)**: Only reach for Chiseled when security compliance strictly requires eliminating all shells and package managers from the runtime image, and after confirming Alpine and Ubuntu Noble do not meet the requirement.

---

## Contoso wrapper images

This repository builds **three** .NET 10 wrapper images on top of the Microsoft bases, with **Alpine as our primary production base**. They share the same operational contract: ports 8080/8443 exposed, ICU-backed globalization, server GC with a managed heap cap, a non-root `contoso` user (UID/GID `7777`) with home `/app`, and `/app/.info` plus `/app/app-data` directories ready for the runtime user.


| Image                                          | Role                               | Source Dockerfile                                                                        | Based on                                              |
| ---------------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `ghcr.io/jbaltikauskas/alpine-net-dotnet-tools-10`          | **Primary Base (Production)**      | [`dockerfiles/alpine/10/Dockerfile`](dockerfiles/alpine/10/Dockerfile)                   | `mcr.microsoft.com/dotnet/aspnet:10.0-alpine`         |
| `ghcr.io/jbaltikauskas/ubuntu-net-dotnet-tools-10`          | Secondary Base (Full Ubuntu)       | [`dockerfiles/ubuntu/10/Dockerfile`](dockerfiles/ubuntu/10/Dockerfile)                   | `mcr.microsoft.com/dotnet/aspnet:10.0-noble`          |
| `ghcr.io/jbaltikauskas/ubuntu-chiseled-net-dotnet-tools-10` | Last-Resort Base (Distroless)      | [`dockerfiles/ubuntu-chiseled/10/Dockerfile`](dockerfiles/ubuntu-chiseled/10/Dockerfile) | `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` |


### Diagnostic CLIs

Every Dockerfile builds one image, target `final`, tagged `:latest`. That stage copies `dockerfiles/.dotnet-tools` (`dotnet-debug`, `dotnet-gcdump`, and `dotnet-trace`) onto `/app/dotnet-tools` and prepends that directory to `PATH`. Run [`.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1`](.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1) before the image build so the tools folder exists. [`alpine/10`](dockerfiles/alpine/10/Dockerfile) publishes `contoso/alpine-net-dotnet-tools-10:latest`, [`ubuntu/10`](dockerfiles/ubuntu/10/Dockerfile) publishes `contoso/ubuntu-net-dotnet-tools-10:latest`, and [`ubuntu-chiseled/10`](dockerfiles/ubuntu-chiseled/10/Dockerfile) publishes `contoso/ubuntu-chiseled-net-dotnet-tools-10:latest`.


| Input            | Default | Effect                                                                                                            |
| ---------------- | ------- | ----------------------------------------------------------------------------------------------------------------- |
| Build target     | `final` | Copies `dotnet-debug`, `dotnet-gcdump`, and `dotnet-trace` under `/app/dotnet-tools` and puts that directory on `PATH`. |
| `DOTNET_VERSION` | `10.0`  | Pins the Microsoft `aspnet` image tag (`${DOTNET_VERSION}-alpine` or `${DOTNET_VERSION}-noble`). Alpine and Ubuntu only. |


```bash
# Alpine — primary, tagged latest
docker build -f dockerfiles/alpine/10/Dockerfile \
  --target final \
  --build-context dotnet-tools=dockerfiles/.dotnet-tools \
  -t contoso/alpine-net-dotnet-tools-10:latest dockerfiles/alpine/10

# Ubuntu Noble — secondary, tagged latest
docker build -f dockerfiles/ubuntu/10/Dockerfile \
  --target final \
  --build-context dotnet-tools=dockerfiles/.dotnet-tools \
  -t contoso/ubuntu-net-dotnet-tools-10:latest dockerfiles/ubuntu/10
```

Published via [`.github/workflows/docker-alpine.yml`](.github/workflows/docker-alpine.yml), [`.github/workflows/docker-ubuntu.yml`](.github/workflows/docker-ubuntu.yml), and [`.github/workflows/docker-ubuntu-chisel.yml`](.github/workflows/docker-ubuntu-chisel.yml). Each workflow tags the image `latest` and with a UTC publish stamp.

What each wrapper adds on top of the upstream Microsoft image:

- **Package update and curated install set.** Alpine uses `apk update && apk upgrade` plus `ca-certificates`, `icu-data-full`, `icu-libs`, `tzdata`. Ubuntu uses `apt update && apt upgrade` plus `libicu74`, `tzdata`, `ca-certificates`, `adduser`. The Chiseled image uses Canonical Chisel to slice in `libicu74_libs`, `tzdata_zoneinfo` (and the legacy zoneinfo slice) without dragging in a package manager.
- **Production ASP.NET environment.** `ASPNETCORE_ENVIRONMENT=Production`, `ASPNETCORE_HTTP_PORTS=8080`, `ASPNETCORE_URLS=http://+:8080`, `DOTNET_RUNNING_IN_CONTAINER=true`, `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`, `LANG`/`LC_ALL=en_US.UTF-8`, `DOTNET_gcServer=1`, `DOTNET_GCHeapHardLimitPercent=46` (hex; **70%** of container memory — scales with the runtime memory limit; override at run time if needed).
- **Exposed ports.** `8080` (HTTP) and `8443` (HTTPS). Kestrel binds 8080 by default; 8443 is exposed for downstream images that wire up HTTPS.
- **Non-root user.** `contoso` (UID/GID `7777`) with home `/app`, `WORKDIR /app`, and ownership/permissions set so the runtime user can read and execute under `/app`. The Chiseled variant also sets `APP_UID=7777` so the standard ASP.NET Core container conventions resolve to the same user.
- **Runtime metadata snapshots.** `/app/.info/dotnet.txt` (`dotnet --info`) and `/app/.info/linux.txt` (`/etc/os-release`) captured at build time.
- **Writable app state directory.** `/app/app-data`, owned by `contoso`, ready for application data.
- **Diagnostic CLIs.** `/app/dotnet-tools` holds `dotnet-debug`, `dotnet-gcdump`, and `dotnet-trace`, and that directory is on `PATH`. Those files come from the [diagnostic tools build](#diagnostic-tools-build), not from `dotnet tool install` inside the image. Chiseled still has no shell, so the binaries are present but cannot be started with `docker exec`.

#### Copy-paste commands

Run these inside the container (`docker exec`) after the app is up. `WORKDIR` is `/app`, so `./app-data` is `/app/app-data`. When a command needs a process, it is PID 1 (the app). `dotnet-debug` takes that id as a positional argument. The same lines are written to `tests/.build/.DotNet-Tools-Commands.txt` by [`Image-TestBuild-DotNet-Tools-TestApp.ps1`](Image-TestBuild-DotNet-Tools-TestApp.ps1) before any image build, and they are commented above the `/app/app-data` copy in [`dockerfiles/alpine/10/Dockerfile`](dockerfiles/alpine/10/Dockerfile).

`dotnet-trace` collect with no `--profile` uses `dotnet-common` and `dotnet-sampled-thread-time`. The CPU line asks for sampled thread time only. The GC line uses `gc-verbose`. `convert` and `report topN` read the file the first command wrote. The old `cpu-sampling` profile is not used.

```text
dotnet-trace collect -o ./app-data/trace.nettrace --process-id 1 --duration 00:00:15
dotnet-trace collect -o ./app-data/trace-cpu.nettrace --process-id 1 --duration 00:00:15 --profile dotnet-sampled-thread-time
dotnet-trace collect -o ./app-data/trace-gc.nettrace --process-id 1 --duration 00:00:15 --profile gc-verbose
dotnet-trace convert ./app-data/trace.nettrace --format Speedscope -o ./app-data/trace.speedscope.json
dotnet-trace report ./app-data/trace.nettrace topN -n 10
```

`dotnet-gcdump` has `collect`, `report`, and `ps`. `collect` triggers a full GC.

```text
dotnet-gcdump collect -o ./app-data/heap.gcdump --process-id 1
dotnet-gcdump collect -o ./app-data/heap-verbose.gcdump --process-id 1 --verbose --timeout 60
dotnet-gcdump report ./app-data/heap.gcdump
dotnet-gcdump report --process-id 1
dotnet-gcdump ps
```

`dotnet-counters` writes a time series. `collect` exits after `--duration` and writes `csv` or `json` under `./app-data`. `monitor` prints `System.Runtime` for the same duration, then exits. `ps` lists .NET processes.

```text
dotnet-counters collect -o ./app-data/counters.csv --format csv --process-id 1 --duration 00:00:15
dotnet-counters collect -o ./app-data/counters.json --format json --process-id 1 --duration 00:00:15 System.Runtime
dotnet-counters monitor --process-id 1 System.Runtime --refresh-interval 1 --duration 00:00:15
dotnet-counters ps
```

`dotnet-debug` attaches to the live process. It does not collect dumps. `-c exit` returns so `docker exec` does not stay in the SOS shell.

```text
dotnet-debug attach 1 -c clrstack -c exit
dotnet-debug attach 1 -c "dumpheap -stat" -c exit
dotnet-debug attach 1 -c clrthreads -c exit
dotnet-debug attach 1 -c threadpool -c exit
dotnet-debug attach 1 -c gcheapstat -c exit
```

Example from the host, Alpine test container:

```powershell
docker exec -it dotnet-tools-testapp-alpine-10 dotnet-trace collect -o ./app-data/trace.nettrace --process-id 1 --duration 00:00:15
```

Upstream `mcr.microsoft.com/dotnet/aspnet:10.0-alpine` and friends are Microsoft's stock images. They do not include any of the above. If you build directly on the stock images, your CI cannot surface regressions tied to the wrapper layers — those layers aren't there.

---

## Multi-stage: stock SDK + Contoso runtime

Build and publish with Microsoft's SDK (`mcr.microsoft.com/dotnet/sdk:10.0-alpine` or `10.0-noble`), then run the published output on **`ghcr.io/jbaltikauskas/alpine-net-dotnet-tools-10`** (our primary recommended base). This ensures local builds and CI inherit our curated environment: security updates, GC and heap caps, non-root user, exposed ports, pre-baked ICU globalization, and `/app` layout.

Stock Microsoft runtime (Alpine), for comparison:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

COPY Directory.Build.props Directory.Packages.props NuGet.config ./
COPY src/Contoso.Platform.Api/Contoso.Platform.Api.csproj src/Contoso.Platform.Api/
COPY src/Contoso.Platform.Application/Contoso.Platform.Application.csproj src/Contoso.Platform.Application/
COPY src/Contoso.Platform.Domain/Contoso.Platform.Domain.csproj src/Contoso.Platform.Domain/
COPY src/Contoso.Platform.Infrastructure/Contoso.Platform.Infrastructure.csproj src/Contoso.Platform.Infrastructure/
RUN dotnet restore src/Contoso.Platform.Api/Contoso.Platform.Api.csproj

COPY . .
RUN dotnet publish src/Contoso.Platform.Api/Contoso.Platform.Api.csproj \
  --configuration Release \
  --no-restore \
  --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "Contoso.Platform.Api.dll"]
```

Contoso-built runtime — swap in the primary hardened Alpine base:

```dockerfile
FROM ghcr.io/jbaltikauskas/alpine-net-dotnet-tools-10 AS runtime

COPY --chown=7777:7777 --from=build /app .
ENTRYPOINT ["dotnet", "Contoso.Platform.Api.dll"]
```

If your workload requires broader native library support or `apt`, swap `alpine-net-dotnet-tools-10` for the secondary `ubuntu-net-dotnet-tools-10` base. Reserve `ubuntu-chiseled-net-dotnet-tools-10` as the last-resort distroless option when policy strictly forbids a shell. The contract on `/app`, the listening port, and the runtime user stays identical across all three.

Each base image is tagged `:latest` and already includes the diagnostic CLIs. See [Diagnostic CLIs](#diagnostic-clis).

---

## Getting started

### Prerequisites

- Docker Engine with BuildKit (`docker buildx` available).
- Git.
- A GitHub account or token only if you plan to push to GHCR (`ghcr.io`).

### Clone

```bash
git clone https://github.com/jbaltikauskas/DotNet-Production-Dockerfiles.git
cd DotNet-Production-Dockerfiles
```

### Local build

Local tags below are for development only. Published image names are the `ghcr.io/jbaltikauskas/...` paths.

```bash
# Alpine .NET 10 (Primary) — always :latest
docker build -f dockerfiles/alpine/10/Dockerfile \
  --target final \
  --build-context dotnet-tools=dockerfiles/.dotnet-tools \
  -t contoso/alpine-net-dotnet-tools-10:latest dockerfiles/alpine/10

# Ubuntu Noble .NET 10 (Secondary) — always :latest
docker build -f dockerfiles/ubuntu/10/Dockerfile \
  --target final \
  --build-context dotnet-tools=dockerfiles/.dotnet-tools \
  -t contoso/ubuntu-net-dotnet-tools-10:latest dockerfiles/ubuntu/10

# Ubuntu Noble Chiseled .NET 10 (Last-resort distroless) — always :latest
docker build -f dockerfiles/ubuntu-chiseled/10/Dockerfile \
  --target final \
  --build-context dotnet-tools=dockerfiles/.dotnet-tools \
  -t contoso/ubuntu-chiseled-net-dotnet-tools-10:latest dockerfiles/ubuntu-chiseled/10
```

### Smoke check

Each image's entrypoint is `dotnet`, so passing `--info` runs `dotnet --info`:

```bash
docker run --rm contoso/alpine-net-dotnet-tools-10:latest --info
docker run --rm contoso/ubuntu-net-dotnet-tools-10:latest --info
docker run --rm contoso/ubuntu-chiseled-net-dotnet-tools-10:latest --info
```

You should see the runtime version, host OS info, and available SDKs/runtimes for that image.

---

## Published images (GHCR)

The CI workflows in `.github/workflows/docker-*.yml` push to GitHub Container Registry at `ghcr.io/<lowercase-owner>/<image-name>`. The owner segment is the GitHub owner of this repository (not the repo name). For `jbaltikauskas`:

```bash
docker pull ghcr.io/jbaltikauskas/alpine-net-dotnet-tools-10
docker pull ghcr.io/jbaltikauskas/ubuntu-net-dotnet-tools-10
docker pull ghcr.io/jbaltikauskas/ubuntu-chiseled-net-dotnet-tools-10
```

The same commands work from PowerShell, Command Prompt, and bash. Each image is tagged `latest` and with a UTC publish stamp `yyyyMMdd-HHmm`. For reproducible builds, pin to a specific stamp tag or a digest rather than `latest`. Public packages pull without authentication; private packages need `docker login ghcr.io`.

Published images are signed with [cosign](https://github.com/sigstore/cosign) via the keyless workflow. The signing step runs against the build digest, so signatures are tied to the exact image content, not the tag.

---

## Troubleshooting

`**docker buildx` not available.** Install or enable Docker Buildx in your Docker installation. Older Docker installs may need an explicit `docker buildx install` or a newer Docker Desktop.

**Cannot pull `mcr.microsoft.com/dotnet/aspnet:10.0-`*.** Check outbound network access to `mcr.microsoft.com` and that the Docker daemon is running. Corporate proxies sometimes need to be added to the Docker engine config.

**GHCR push or auth errors.** Authenticate Docker to GHCR (`docker login ghcr.io`) and confirm the token has `write:packages`. The workflow uses `GITHUB_TOKEN` with `packages: write`, which requires the package to allow the repo as a source.

**Chiseled image won't open a shell.** That's expected — there is no shell. For debugging, copy a busybox or debug sidecar image into the same pod, or rebuild against the full Ubuntu Noble image (`ubuntu-net-dotnet-tools-10`) temporarily.

**Alpine app throws `DllNotFoundException`.** The library is almost always missing a musl-compatible native dep. Either add the appropriate `apk` packages, or switch the base to `ubuntu-net-dotnet-tools-10` (secondary choice) and run on glibc.

---

## Diagnostic tools build

Every image needs `dotnet-debug`, `dotnet-gcdump`, and `dotnet-trace` on `PATH` under `/app/dotnet-tools`. Installing those CLIs with `dotnet tool install` inside the Dockerfile copies three full NuGet trees and adds about **136 MB** to the image. This repository instead runs [`.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1`](.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1) first: it merges the three packages into one Linux x64 folder at `dockerfiles/.dotnet-tools` (~28–30 MB), and the image copies that.

**Why.** Each `dotnet tool install` tree keeps its own copy of shared framework assemblies, plus culture satellites, PDBs, XML docs, and Windows / macOS / ARM runtimes a Linux container never loads. The merge script drops that duplication so the `:latest` images stay useful for dumps and traces without the 136 MB layer.

This section is the short version. The [step-by-step diagnostic tools build](docs/diagnostic-tools-build.md) has the walkthrough, screenshots, and copy rules.

---

## DotNet-Tools-TestApp

[`tests/DotNet-Tools-TestApp`](tests/DotNet-Tools-TestApp/README.md) is a small .NET 10 console workload used to exercise the diagnostic CLIs (`dotnet-trace`, `dotnet-gcdump`, `dotnet-debug`, `dotnet-counters`). The project is **x64-only** (`<Platforms>x64</Platforms>`, `<PlatformTarget>x64</PlatformTarget>`, `net10.0`).

The process runs an endless loop that on every iteration:

1. Reads a ~10 MB JSON dataset (`Resources/people.json`) embedded as a managed resource.
2. Deserializes it into a strongly-typed `List<Person>` (record types with nested `Address`).
3. Runs LINQ aggregations (group by state, average salary, top earner).
4. Re-serializes derived data, and every 10th iteration re-serializes the full payload to stress the large object heap.
5. Sleeps for a short interval (default 10 ms) and repeats.

Every 20 iterations it prints per-iteration timing, cumulative GC counts, and the current working set, so you can correlate its output with what the diagnostic tools see. The app prints its PID on startup — use that with the diagnostic tools.

| Flag            | Default | Description                                     |
| --------------- | ------- | ----------------------------------------------- |
| `--interval-ms` | `10`    | Sleep between iterations in milliseconds.       |
| `--iterations`  | `0`     | Stop after N iterations. `0` means run forever. |

```powershell
# Infinite loop, 10 ms between iterations (defaults)
dotnet run --project tests/DotNet-Tools-TestApp -c Release -p:Platform=x64

# Bounded smoke run (no attach)
dotnet run --project tests/DotNet-Tools-TestApp -c Release -p:Platform=x64 -- --iterations 25 --interval-ms 50
```

Build, self-contained publish, and attach commands (`dotnet-trace`, `dotnet-gcdump`, `dotnet-counters`, `dotnet-debug`) are in the [test app README](tests/DotNet-Tools-TestApp/README.md). The tools images, test-app images, and detached containers are built by [DotNet-Tools test images](docs/dotnet-tools-test-images.md).

---

## Building images on your local machine (PowerShell)

The repository ships four PowerShell 7.2+ scripts that wrap `docker buildx build` with the exact `--target`, `--build-arg`, `--build-context`, and tagging conventions documented in each Dockerfile. Use these instead of hand-typed `docker build` lines so local builds stay in sync with CI.

| Script                              | Purpose                                    | Produces                                                                  |
| ----------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------- |
| [`Image-Build-All.ps1`](Image-Build-All.ps1)                             | Orchestrator: runs the three per-distro scripts below | Every Contoso image below, each tagged `:latest`                           |
| [`Image-Build-Alpine.ps1`](Image-Build-Alpine.ps1)                     | Alpine only (**primary**)                  | `contoso/alpine-net-dotnet-tools-10:latest`              |
| [`Image-Build-Ubuntu.ps1`](Image-Build-Ubuntu.ps1)                     | Ubuntu Noble only (secondary)              | `contoso/ubuntu-net-dotnet-tools-10:latest`              |
| [`Image-Build-Ubuntu-Chiseled.ps1`](Image-Build-Ubuntu-Chiseled.ps1)            | Ubuntu Chiseled only (last-resort)         | `contoso/ubuntu-chiseled-net-dotnet-tools-10:latest` |

`Image-Build-All.ps1` is a thin orchestrator: it invokes `Image-Build-Alpine.ps1`, `Image-Build-Ubuntu.ps1`, and `Image-Build-Ubuntu-Chiseled.ps1` in that order, forwarding `-NoCache`. It builds no images itself and stops immediately if any per-distro script fails. Use a per-distro script directly when you need to build a single distro.

Reusable helper functions live under [`.ps/ImageBuild/Core/`](.ps/ImageBuild/Core/) (one function per file). The three per-distro entry scripts dot-source the build helpers and the exit helpers (`Write-ImageBuildError`, `Write-ImageBuildSuccess`). `Image-Build-All.ps1` does not touch these — the per-distro scripts it calls load them:

- [`Assert-ImageBuildDockerCli.ps1`](.ps/ImageBuild/Core/Assert-ImageBuildDockerCli.ps1)
- [`Invoke-DockerImageBuild.ps1`](.ps/ImageBuild/Core/Invoke-DockerImageBuild.ps1)
- [`Invoke-ImageBuildBatch.ps1`](.ps/ImageBuild/Core/Invoke-ImageBuildBatch.ps1)
- [`Write-ImageBuildSettings.ps1`](.ps/ImageBuild/Core/Write-ImageBuildSettings.ps1)
- [`Write-ImageBuildSummary.ps1`](.ps/ImageBuild/Core/Write-ImageBuildSummary.ps1)
- [`Write-ImageBuildError.ps1`](.ps/ImageBuild/Core/Write-ImageBuildError.ps1)
- [`Write-ImageBuildSuccess.ps1`](.ps/ImageBuild/Core/Write-ImageBuildSuccess.ps1)

### Prerequisites

- PowerShell 7.2 or later (`pwsh`).
- Docker Engine with BuildKit (`docker buildx` on PATH).
- Run [`.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1`](.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1) first to populate `dockerfiles/.dotnet-tools`. See [Diagnostic tools build](#diagnostic-tools-build). Every image build copies that folder.

### Parameters

| Parameter  | Values                          | Default | Effect                                                                                                    |
| ---------- | ------------------------------- | ------- | --------------------------------------------------------------------------------------------------------- |
| `-NoCache` | `$true`, `$false`               | `$true` | Shared by all four scripts. `Image-Build-All.ps1` forwards it verbatim to each per-distro script. `$true` passes `--no-cache` (matches the Copy-and-Paste examples in each Dockerfile). |
| `-WaitOnExit` | switch                       | off     | **Only on the three per-distro scripts.** Waits for Enter after success or failure so a double-clicked window stays open. Omit it in a terminal or CI run. `Image-Build-All.ps1` does not accept it. |

### Usage examples

#### All three images — [`Image-Build-All.ps1`](Image-Build-All.ps1)

Thin orchestrator that runs the three per-distro scripts below in order (Alpine, Ubuntu Noble, Ubuntu Chiseled). Stops immediately if any sub-script fails. To narrow the scope, invoke a per-distro script directly.

```powershell
.\Image-Build-All.ps1
.\Image-Build-All.ps1 -NoCache:$false
```

#### Alpine only — [`Image-Build-Alpine.ps1`](Image-Build-Alpine.ps1) (**primary**)

```powershell
.\Image-Build-Alpine.ps1
.\Image-Build-Alpine.ps1 -NoCache:$false
```

#### Ubuntu Noble only — [`Image-Build-Ubuntu.ps1`](Image-Build-Ubuntu.ps1) (secondary)

```powershell
.\Image-Build-Ubuntu.ps1
.\Image-Build-Ubuntu.ps1 -NoCache:$false
```

#### Ubuntu Chiseled only — [`Image-Build-Ubuntu-Chiseled.ps1`](Image-Build-Ubuntu-Chiseled.ps1) (last-resort distroless)

```powershell
.\Image-Build-Ubuntu-Chiseled.ps1
.\Image-Build-Ubuntu-Chiseled.ps1 -NoCache:$false
```

### Typical local workflows

```powershell
# 1. First-time or after upstream servicing bumps: refresh diagnostic tools, then build every image.
.\.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1
.\Image-Build-All.ps1

# 2. Iterating on the Alpine Dockerfile only, reusing BuildKit cache for speed.
.\Image-Build-Alpine.ps1 -NoCache:$false

# 3. Rebuilding one distro. Each script tags its image :latest.
.\Image-Build-Ubuntu.ps1
```

The scripts stream `docker buildx build` output live, exit non-zero on any docker failure, and end with a cyan `Built N image(s):` summary listing every tag produced. They return immediately unless you pass `-WaitOnExit`.
