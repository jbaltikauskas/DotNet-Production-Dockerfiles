using DotNet.Tools.TestApp;

// -----------------------------------------------------------------------------
// DotNet-Tools-TestApp
//
// A small .NET 10 console workload designed for exercising the .NET diagnostic
// tools (dotnet-trace, dotnet-gcdump, dotnet-debug, dotnet-counters, ...).
//
// It runs an endless loop that on every iteration:
//   1. Reads the embedded ~10MB people.json resource.
//   2. Deserializes it into a strongly-typed List<Person>.
//   3. Performs a few light-weight transformations / LINQ queries.
//   4. Serializes the result back to JSON.
//   5. Sleeps for a short interval (default 10 ms) before repeating.
//
// The process prints its PID on startup so the diagnostic CLIs can attach:
//
//   dotnet-trace   collect   -p <pid> --providers Microsoft-DotNETCore-SampleProfiler
//   dotnet-gcdump  collect   -p <pid>
//   dotnet-counters monitor  -p <pid>
//   dotnet-debug   ...
// -----------------------------------------------------------------------------

const string resourceName = "DotNet.Tools.TestApp.Resources.people.json";

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    Console.WriteLine();
    Console.WriteLine("Ctrl+C received. Requesting shutdown...");
    Cts.Cancel();
};

var loopIntervalMs = ParseIntArg(args, "--interval-ms", 10);
var maxIterations  = ParseIntArg(args, "--iterations", 0); // 0 = infinite

Console.WriteLine("=== DotNet-Tools-TestApp ===");
Console.WriteLine($"PID:            {Environment.ProcessId}");
Console.WriteLine($"Runtime:        {Environment.Version} ({System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier})");
Console.WriteLine($"Process arch:   {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");
Console.WriteLine($"Server GC:      {System.Runtime.GCSettings.IsServerGC}");
Console.WriteLine($"Interval (ms):  {loopIntervalMs}");
Console.WriteLine($"Iterations:     {(maxIterations == 0 ? "infinite" : maxIterations.ToString())}");
Console.WriteLine();

var jsonBytes = LoadEmbeddedResource(resourceName);
Console.WriteLine($"Embedded JSON resource: {resourceName} ({jsonBytes.Length:N0} bytes)");

var readOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web)
{
    PropertyNameCaseInsensitive = true,
};

var writeOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web)
{
    WriteIndented = false,
};

// Warm up so the very first iteration doesn't dominate JIT / tiering timings.
_ = JsonSerializer.Deserialize<List<Person>>(jsonBytes, readOptions)
    ?? throw new InvalidOperationException("Failed to deserialize warm-up payload.");

long   iteration    = 0;
long   totalPeople  = 0;
double totalMs      = 0;
var    processSw    = Stopwatch.StartNew();

while (!Cts.IsCancellationRequested)
{
    iteration++;

    var iterSw = Stopwatch.StartNew();

    // 1) Deserialize the embedded JSON payload.
    var people = JsonSerializer.Deserialize<List<Person>>(jsonBytes, readOptions)
        ?? throw new InvalidOperationException("Deserialization returned null.");

    // 2) Do a bit of work so profilers have interesting stacks.
    var activeByState = people
        .Where(p => p.IsActive)
        .GroupBy(p => p.Address.State)
        .Select(g => new
        {
            State       = g.Key,
            Count       = g.Count(),
            AvgSalary   = g.Average(p => p.Salary),
            TopEarner   = g.OrderByDescending(p => p.Salary).First().FullName(),
        })
        .OrderByDescending(x => x.Count)
        .Take(5)
        .ToList();

    // 3) Serialize a derived payload back to JSON (churns Gen0 allocations).
    _ = JsonSerializer.Serialize(activeByState, writeOptions);

    // 4) Serialize the full list too, every 10th iteration, to grow LOH usage
    //    and give dotnet-gcdump something to chew on.
    if (iteration % 10 == 0)
    {
        _ = JsonSerializer.SerializeToUtf8Bytes(people, writeOptions);
    }

    iterSw.Stop();
    totalPeople += people.Count;
    totalMs     += iterSw.Elapsed.TotalMilliseconds;

    if (iteration % 20 == 0 || iteration == 1)
    {
        var proc = Process.GetCurrentProcess();

        Console.WriteLine(
            $"[iter {iteration,6}]  people={people.Count,5}  " +
            $"top-state={activeByState.FirstOrDefault()?.State ?? "-",-3}  " +
            $"iter={iterSw.Elapsed.TotalMilliseconds,7:F2} ms  " +
            $"avg={totalMs / iteration,6:F2} ms  " +
            $"gen0={GC.CollectionCount(0)} gen1={GC.CollectionCount(1)} gen2={GC.CollectionCount(2)}  " +
            $"workingSet={proc.WorkingSet64 / (1024 * 1024)} MB  " +
            $"uptime={processSw.Elapsed:hh\\:mm\\:ss}");
    }

    if (maxIterations > 0 && iteration >= maxIterations)
    {
        Console.WriteLine($"Reached configured iteration limit ({maxIterations}). Exiting.");
        break;
    }

    try
    {
        await Task.Delay(loopIntervalMs, Cts.Token).ConfigureAwait(false);
    }
    catch (TaskCanceledException)
    {
        break;
    }
}

Console.WriteLine();
Console.WriteLine("=== Summary ===");
Console.WriteLine($"Iterations:      {iteration:N0}");
Console.WriteLine($"People processed:{totalPeople:N0}");
Console.WriteLine($"Total wall time: {processSw.Elapsed}");
Console.WriteLine($"Avg iter time:   {(iteration == 0 ? 0 : totalMs / iteration):F2} ms");

return 0;


static byte[] LoadEmbeddedResource(string name)
{
    var asm    = Assembly.GetExecutingAssembly();

    using var s = asm.GetManifestResourceStream(name)
        ?? throw new InvalidOperationException(
            $"Embedded resource '{name}' not found. Available: " +
            string.Join(", ", asm.GetManifestResourceNames()));

    using var ms = new MemoryStream(capacity: (int)s.Length);
    s.CopyTo(ms);

    return ms.ToArray();
}

static int ParseIntArg(string[] argv, string flag, int fallback)
{
    for (var i = 0; i < argv.Length - 1; i++)
    {
        if (string.Equals(argv[i], flag, StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(argv[i + 1], out var v))
        {
            return v;
        }
    }

    return fallback;
}

// Program-level statics live at the bottom of the top-level file.
static partial class Program
{
    private static readonly CancellationTokenSource Cts = new();
}
