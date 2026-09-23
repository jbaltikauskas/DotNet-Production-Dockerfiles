# DotNet-Tools-TestApp

Small .NET 10 console workload used to exercise the .NET diagnostic CLI tools
(`dotnet-trace`, `dotnet-gcdump`, `dotnet-debug`, `dotnet-counters`, ...).

The process runs an endless loop that on every iteration:

1. Reads a ~10 MB JSON dataset (`Resources/people.json`) embedded as a managed
   resource.
2. Deserializes it into a strongly-typed `List<Person>` (record types with
   nested `Address`).
3. Runs a couple of LINQ aggregations (group by state, avg salary, top earner).
4. Re-serializes derived data, and every 10th iteration re-serializes the full
   payload to stress the LOH.
5. Sleeps for a short interval (default 10 ms) and repeats.

Every 20 iterations it prints per-iteration timing, cumulative GC counts, and
the current working set, so you can correlate its output with what the
diagnostic tools see.

## Quick usage

```powershell
dotnet run --project tests/DotNet-Tools-TestApp -c Release -p:Platform=x64
# Then in another shell, using the printed PID:
dotnet-trace    collect -p <pid> --duration 00:00:30 --providers Microsoft-DotNETCore-SampleProfiler
dotnet-gcdump   collect -p <pid>
dotnet-counters monitor -p <pid> System.Runtime
dotnet-debug    attach --process-id <pid>
```

Bounded smoke run (no attach):

```powershell
dotnet run --project tests/DotNet-Tools-TestApp -c Release -p:Platform=x64 -- --iterations 25 --interval-ms 50
```

## Build

The project is **x64-only** (`<Platforms>x64</Platforms>`,
`<PlatformTarget>x64</PlatformTarget>`).

```powershell
dotnet build tests/DotNet-Tools-TestApp/DotNet-Tools-TestApp.csproj -c Release -p:Platform=x64
```

Self-contained publish (Windows or Linux, x64):

```powershell
dotnet publish tests/DotNet-Tools-TestApp/DotNet-Tools-TestApp.csproj -c Release -r win-x64   --self-contained true
dotnet publish tests/DotNet-Tools-TestApp/DotNet-Tools-TestApp.csproj -c Release -r linux-x64 --self-contained true
```

## Run

```powershell
# Infinite loop, 10 ms between iterations (defaults)
dotnet run --project tests/DotNet-Tools-TestApp -c Release -p:Platform=x64

# Bounded run for CI: 100 iterations, 100 ms interval
dotnet run --project tests/DotNet-Tools-TestApp -c Release -p:Platform=x64 -- --iterations 100 --interval-ms 100
```

CLI arguments:

| Flag             | Default | Description                                      |
| ---------------- | ------- | ------------------------------------------------ |
| `--interval-ms`  | `10`    | Sleep between iterations in milliseconds.         |
| `--iterations`   | `0`     | Stop after N iterations. `0` means run forever.  |

The app prints its PID on startup — use that with the diagnostic tools.

## Attach the diagnostic tools

```powershell
# CPU profile for 30 seconds
dotnet-trace collect -p <pid> --duration 00:00:30 `
  --providers Microsoft-DotNETCore-SampleProfiler

# Managed heap dump
dotnet-gcdump collect -p <pid>

# Live counters
dotnet-counters monitor -p <pid> System.Runtime

# Interactive debugger (dotnet-debug)
dotnet-debug attach --process-id <pid>
```

## Layout

```
tests/DotNet-Tools-TestApp/
├── DotNet-Tools-TestApp.csproj   # x64-only, net10.0, embeds people.json
├── Program.cs                    # Loop, arg parsing, per-iter reporting
├── Person.cs                     # Person / Address records + JsonContext
├── Resources/
│   └── people.json               # ~10 MB, 14,110 synthetic person records
└── README.md
```
