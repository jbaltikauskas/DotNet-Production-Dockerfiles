# DotNet-Tools test images

[`Image-TestBuild-DotNet-Tools-TestApp.ps1`](../Image-TestBuild-DotNet-Tools-TestApp.ps1) is the orchestrator for the diagnostics-tools test flow. For `-DotNetVersion 10` (the default) it:

1. Builds the three Contoso diagnostics-tools base images.
2. Builds [`DotNet-Tools-TestApp`](../tests/DotNet-Tools-TestApp/README.md) for `linux-x64`.
3. Layers that publish output onto each tools base as three runnable test-app images.
4. Starts those three containers **detached**.

The script owns the order of that flow. Later steps (attach `dotnet-trace` / `dotnet-gcdump` / `dotnet-debug` to a running container) will be added after the steps below. A failure in any step stops the run.

## What it does today

Run from the repository root:

```powershell
.\Image-TestBuild-DotNet-Tools-TestApp.ps1
```

Top-down flow:

1. Resolve the repository root (the folder that contains this script), then the `tests` folder under it.
2. Load `Write-ImageBuildError` and `Write-ImageBuildSuccess` from [`.ps/ImageBuild/Core/`](../.ps/ImageBuild/Core/) so a failed or successful run prints the same banners as the image-build scripts.
3. Confirm the three per-distro scripts and the test-app build script exist. A missing file throws before any build starts.
4. Write [`tests/.build/.DotNet-Tools-Commands.txt`](../tests/.build/.DotNet-Tools-Commands.txt) before any `docker build`. The file lists the in-container `dotnet-trace`, `dotnet-gcdump`, `dotnet-counters`, and `dotnet-debug` commands (PID 1, output under `./app-data`). The same commands are in the [root README](../README.md#copy-paste-commands).
5. Build the Alpine diagnostics-tools image.
6. Build the Ubuntu diagnostics-tools image.
7. Build the Ubuntu Chiseled diagnostics-tools image.
8. Invoke [`.ps/TestApp/Build-DotNet-Tools-TestApp.ps1`](../.ps/TestApp/Build-DotNet-Tools-TestApp.ps1), which:
   - restores and builds the test app for `linux-x64`
   - copies artifacts to `tests\.build`
   - builds the three test-app images
   - starts each container with `docker run -d`

Step 4 writes the commands file into `tests\.build` (the folder is created when it is missing). Steps 5–7 invoke the per-distro entry scripts with `-ToolsOnly` and forward `-DotNetVersion` and `-NoCache`. Step 8 forwards `-BuildConfiguration`, `-DotNetVersion`, and `-NoCache`. The artifact copy in step 8 leaves `.gitignore`, `.dockerignore`, and `.DotNet-Tools-Commands.txt` in place.

```text
Image-TestBuild-DotNet-Tools-TestApp.ps1
    │
    ├─ tests\.build\.DotNet-Tools-Commands.txt
    ├─ Image-Build-Alpine.ps1            -ToolsOnly -DotNetVersion 10
    ├─ Image-Build-Ubuntu.ps1            -ToolsOnly -DotNetVersion 10
    ├─ Image-Build-Ubuntu-Chiseled.ps1   -ToolsOnly -DotNetVersion 10
    │
    └─ .ps\TestApp\Build-DotNet-Tools-TestApp.ps1
           ├─ dotnet restore/build + copy to tests\.build
           ├─ docker buildx build  (alpine / ubuntu / ubuntu-chiseled test-app)
           └─ docker run -d        (three detached containers)
```

`-WaitOnExit` is not forwarded. The orchestrator is for a terminal or CI run and returns as soon as the last step finishes. The elevated launcher [`01-Step--DotNetBuild-Debug.bat`](../tests/01-Step--DotNetBuild-Debug.bat) runs only the test-app script (with `-WaitOnExit`) so that window stays open.

## Images produced (`-DotNetVersion 10`)

| Kind | Tag |
| --- | --- |
| Tools base (Alpine) | `contoso/alpine-net-dotnet-tools-10:latest` |
| Tools base (Ubuntu) | `contoso/ubuntu-net-dotnet-tools-10:latest` |
| Tools base (Ubuntu Chiseled) | `contoso/ubuntu-chiseled-net-dotnet-tools-10:latest` |
| Test app (Alpine) | `contoso/alpine-net-dotnet-tools-testapp-10:latest` |
| Test app (Ubuntu) | `contoso/ubuntu-net-dotnet-tools-testapp-10:latest` |
| Test app (Ubuntu Chiseled) | `contoso/ubuntu-chiseled-net-dotnet-tools-testapp-10:latest` |

## Detached containers (`-DotNetVersion 10`)

After the test-app images build, [`.ps/TestApp/Build-DotNet-Tools-TestApp.ps1`](../.ps/TestApp/Build-DotNet-Tools-TestApp.ps1) starts one detached container per image. Re-runs call `docker rm -f` on any prior container with the same name, then `docker run -d --name <name> <tag>`.

| Distro | Image | Container name |
| --- | --- | --- |
| Alpine | `contoso/alpine-net-dotnet-tools-testapp-10:latest` | `dotnet-tools-testapp-alpine-10` |
| Ubuntu | `contoso/ubuntu-net-dotnet-tools-testapp-10:latest` | `dotnet-tools-testapp-ubuntu-10` |
| Ubuntu Chiseled | `contoso/ubuntu-chiseled-net-dotnet-tools-testapp-10:latest` | `dotnet-tools-testapp-ubuntu-chiseled-10` |

Naming pattern: `dotnet-tools-testapp-<distro>-<DotNetVersion>`.

Each container runs as non-root `contoso` (UID/GID `7777`), working directory `/app` (infinite workload loop by default — see the [test app README](../tests/DotNet-Tools-TestApp/README.md)). Ubuntu and Ubuntu Chiseled start the glibc apphost `/app/DotNet-Tools-TestApp`. Alpine starts `dotnet /app/DotNet-Tools-TestApp.dll`, because that apphost is linked to `/lib64/ld-linux-x86-64.so.2` and Alpine has no glibc loader. Diagnostic CLIs from the tools base are on `PATH` under `/app/dotnet-tools`. In every image the runtime is PID 1.

Useful commands after a successful run:

```powershell
# List the three detached containers
docker ps --filter "name=dotnet-tools-testapp-"

# Follow app stdout (PID, iteration timing, GC counts)
docker logs -f dotnet-tools-testapp-alpine-10
docker logs -f dotnet-tools-testapp-ubuntu-10
docker logs -f dotnet-tools-testapp-ubuntu-chiseled-10

# Exec into Alpine or Ubuntu (Chiseled has no shell)
docker exec -it dotnet-tools-testapp-alpine-10 sh
docker exec -it dotnet-tools-testapp-ubuntu-10  bash

# Stop and remove all three
docker rm -f `
  dotnet-tools-testapp-alpine-10 `
  dotnet-tools-testapp-ubuntu-10 `
  dotnet-tools-testapp-ubuntu-chiseled-10
```

One-shot foreground smoke run (does not use the detached names):

```powershell
docker run --rm contoso/alpine-net-dotnet-tools-testapp-10:latest --iterations 5 --interval-ms 50
```

## Step 1 — diagnostics-tools images

The three scripts live at the repository root. With `-ToolsOnly` each one builds the Dockerfile stage named `final`. That stage copies `dockerfiles/.dotnet-tools` into the image and puts it on `PATH` under `/app/dotnet-tools`. The folder is produced first by [`.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1`](../.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1) (`dotnet-debug`, `dotnet-gcdump`, `dotnet-trace`, merged for Linux x64).

| Order | Script | Image |
| --- | --- | --- |
| 1 | [`Image-Build-Alpine.ps1`](../Image-Build-Alpine.ps1) | `contoso/alpine-net-dotnet-tools-10:latest` |
| 2 | [`Image-Build-Ubuntu.ps1`](../Image-Build-Ubuntu.ps1) | `contoso/ubuntu-net-dotnet-tools-10:latest` |
| 3 | [`Image-Build-Ubuntu-Chiseled.ps1`](../Image-Build-Ubuntu-Chiseled.ps1) | `contoso/ubuntu-chiseled-net-dotnet-tools-10:latest` |

Alpine is the primary base, Ubuntu Noble is the secondary base, and Ubuntu Chiseled is the last-resort distroless image. The same order is used by [`Image-Build-All.ps1`](../Image-Build-All.ps1).

`-DotNetVersion` defaults to `10`. It selects `dockerfiles/<distro>/10` and the `10` segment of each tag. The same value is forwarded to every per-distro script and to the test-app script.

`-ToolsOnly` keeps this run on the `final` stage. The lean images (`contoso/alpine-net-10`, `contoso/ubuntu-net-10`, `contoso/ubuntu-chiseled-net-10`) are built by running a per-distro script, or `Image-Build-All.ps1`, without `-ToolsOnly`.

`-NoCache` defaults to `$true`, which passes `--no-cache` to `docker buildx build` and matches the Copy-and-Paste examples in each Dockerfile. Pass `-NoCache:$false` to allow the BuildKit cache while iterating.

## Step 2 — .NET test app

After the three tools images succeed, the orchestrator runs [`.ps/TestApp/Build-DotNet-Tools-TestApp.ps1`](../.ps/TestApp/Build-DotNet-Tools-TestApp.ps1). That script owns the rest of the flow (this step plus Step 3).

That script first:

1. Stops `VBCSCompiler` and `MSBuild` when they are running, so a previous build cannot lock the output.
2. Checks that `dotnet` is on `PATH`.
3. Finds the first `*.slnx` under [`tests/DotNet-Tools-TestApp`](../tests/DotNet-Tools-TestApp/). Today that file is `DotNet-Tools-TestApp.slnx`.
4. Restores and rebuilds the solution for `linux-x64` only, platform `x64`, with `/p:EnableLocalDevelopment=true`.
5. Copies the build output into [`tests/.build`](../tests/.build/), leaving `.gitignore`, `.dockerignore`, and `.DotNet-Tools-Commands.txt` in place and replacing everything else.

The app targets `net10.0` and is x64-only. Portable PDBs stay in the output so `dotnet-trace` and `dotnet-debug` can show useful stacks. What the process does at runtime is described in the [test app README](../tests/DotNet-Tools-TestApp/README.md).

`-BuildConfiguration` on the orchestrator is forwarded as `-buildConfiguration`. The default is `Debug`.

Output folder for a Debug build, before the copy:

```text
tests/DotNet-Tools-TestApp/bin/x64/Debug/net10.0/linux-x64/
```

After the copy, the same files are in:

```text
tests/.build/
```

Typical contents of `tests/.build/` used as the Docker build context:

| File | Role |
| --- | --- |
| `DotNet-Tools-TestApp` | Linux ELF apphost — image `ENTRYPOINT` |
| `DotNet-Tools-TestApp.dll` | Managed assembly |
| `DotNet-Tools-TestApp.deps.json` | Dependency manifest |
| `DotNet-Tools-TestApp.runtimeconfig.json` | Runtime config (`net10.0`) |
| `DotNet-Tools-TestApp.pdb` | Portable symbols for diagnostics |
| `.dockerignore` | Excludes `.gitignore` from the image |
| `.gitignore` | Kept on disk; not copied into `/app` |
| `.DotNet-Tools-Commands.txt` | In-container diagnostic commands; written before `docker build` and kept across the artifact copy |

## Step 3 — test-app images and detached containers

After the linux-x64 artifacts land in `tests\.build`, the same script builds one runnable image per diagnostics-tools base, then starts each container detached (see [Detached containers](#detached-containers--dotnetversion-10) above).

Each Dockerfile under [`tests/dockerfiles`](../tests/dockerfiles/) starts from the matching tools image and copies the publish output into `/app` as `contoso:contoso` (UID/GID `7777`). Ubuntu and Ubuntu Chiseled set:

```dockerfile
ENTRYPOINT ["/app/DotNet-Tools-TestApp"]
```

Alpine sets `ENTRYPOINT ["dotnet", "/app/DotNet-Tools-TestApp.dll"]`. The shared `tests/.build` apphost is `linux-x64` (glibc). Executing it on Alpine fails with `no such file or directory` because musl does not provide `/lib64/ld-linux-x86-64.so.2`. The managed DLL is the same file on all three images.

| Order | Dockerfile | Base image | Test-app tag |
| --- | --- | --- | --- |
| 1 | [`tests/dockerfiles/alpine/Dockerfile`](../tests/dockerfiles/alpine/Dockerfile) | `contoso/alpine-net-dotnet-tools-10:latest` | `contoso/alpine-net-dotnet-tools-testapp-10:latest` |
| 2 | [`tests/dockerfiles/ubuntu/Dockerfile`](../tests/dockerfiles/ubuntu/Dockerfile) | `contoso/ubuntu-net-dotnet-tools-10:latest` | `contoso/ubuntu-net-dotnet-tools-testapp-10:latest` |
| 3 | [`tests/dockerfiles/ubuntu-chiseled/Dockerfile`](../tests/dockerfiles/ubuntu-chiseled/Dockerfile) | `contoso/ubuntu-chiseled-net-dotnet-tools-10:latest` | `contoso/ubuntu-chiseled-net-dotnet-tools-testapp-10:latest` |

Build context is always `tests/.build`. Ubuntu `chmod 755` the apphost in the final stage; Ubuntu Chiseled applies permissions in a short `busybox` stage because the chiseled base is scratch (no shell). Alpine does not execute the apphost.

Requires the matching tools bases to already exist locally (Step 1 when using the orchestrator). Running the test-app script alone without those bases fails at `docker build`.

## Parameters

| Parameter | Values | Default | Effect |
| --- | --- | --- | --- |
| `-DotNetVersion` | .NET major version, such as `10` | `10` | Forwarded to each per-distro script and the test-app script. Selects Dockerfile folders, image tag segments, and container name suffixes. |
| `-NoCache` | `$true`, `$false` | `$true` | Forwarded to each per-distro script and the test-app script. `$true` passes `--no-cache`. |
| `-BuildConfiguration` | `Debug`, `Release`, or a custom configuration | `Debug` | Forwarded to the test-app build script as `-buildConfiguration`. |

The test-app script also accepts `-solutionFileName`, `-WaitOnExit`, and the same `-DotNetVersion` / `-NoCache` when invoked directly.

## Usage

From the repository root, with PowerShell 7.2 or later:

```powershell
# Full flow: tools images → Debug app → test-app images → detached containers
.\Image-TestBuild-DotNet-Tools-TestApp.ps1

# Reuse the BuildKit cache while iterating on a Dockerfile
.\Image-TestBuild-DotNet-Tools-TestApp.ps1 -NoCache:$false

# Same flow with a Release test app
.\Image-TestBuild-DotNet-Tools-TestApp.ps1 -BuildConfiguration Release

# Explicit .NET 10 (the default) — tags and container names end in -10
.\Image-TestBuild-DotNet-Tools-TestApp.ps1 -DotNetVersion 10
```

Rebuild the test app, its three images, and restart the detached containers **without** rebuilding the tools bases (tools images must already exist):

```powershell
.\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1
.\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1 -buildConfiguration Release
.\.ps\TestApp\Build-DotNet-Tools-TestApp.ps1 -DotNetVersion 10 -NoCache:$false
```

`01-Step--DotNetBuild-Debug.bat` launches that same script elevated and waits for Enter.

## Prerequisites

- PowerShell 7.2 or later (`pwsh`).
- Docker Engine with BuildKit (`docker buildx` on `PATH`) for the image and container steps.
- The .NET 10 SDK (`dotnet` on `PATH`) for the test-app compile step.
- `dockerfiles/.dotnet-tools` already populated. Refresh it with [`.ps\Diagnostics-Tools-Build\DotNet-Tools.ps1`](../.ps/Diagnostics-Tools-Build/DotNet-Tools.ps1) before the first tools-image build, and again after a diagnostics-tool servicing bump. See the [diagnostic tools build](diagnostic-tools-build.md).

## When a step fails

`$ErrorActionPreference` is `Stop`. The first missing script, failed image build, failed `dotnet` build, or failed `docker run` is caught, printed by `Write-ImageBuildError` (exception type, exception message, red failure line), and the process exits with code 1. Steps after the failure do not run. A clean run ends with the green line from `Write-ImageBuildSuccess`.

## Later steps

This script is the list of test steps, in order. The three steps above (tools images, .NET build, test-app images + detached containers) are the whole list today. The next steps — attach the diagnostic CLIs to a running detached container — will be added after the detached runs, in this same file, with the same rule: one failed step ends the run.
