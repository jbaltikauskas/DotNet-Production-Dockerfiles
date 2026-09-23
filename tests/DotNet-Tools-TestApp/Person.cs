namespace DotNet.Tools.TestApp;

public sealed record Address(
    [property: JsonPropertyName("Street")]     string Street,
    [property: JsonPropertyName("City")]       string City,
    [property: JsonPropertyName("State")]      string State,
    [property: JsonPropertyName("PostalCode")] string PostalCode,
    [property: JsonPropertyName("Country")]    string Country);

public sealed record Person(
    [property: JsonPropertyName("Id")]          Guid Id,
    [property: JsonPropertyName("FirstName")]   string FirstName,
    [property: JsonPropertyName("LastName")]    string LastName,
    [property: JsonPropertyName("MiddleName")]  string? MiddleName,
    [property: JsonPropertyName("Email")]       string Email,
    [property: JsonPropertyName("PhoneNumber")] string PhoneNumber,
    [property: JsonPropertyName("DateOfBirth")] DateOnly DateOfBirth,
    [property: JsonPropertyName("Address")]     Address Address,
    [property: JsonPropertyName("Company")]     string Company,
    [property: JsonPropertyName("JobTitle")]    string JobTitle,
    [property: JsonPropertyName("Salary")]      decimal Salary,
    [property: JsonPropertyName("IsActive")]    bool IsActive,
    [property: JsonPropertyName("CreatedAt")]   DateTimeOffset CreatedAt,
    [property: JsonPropertyName("Tags")]        IReadOnlyList<string> Tags,
    [property: JsonPropertyName("Notes")]       string Notes);

/// <summary>
/// System.Text.Json source-generated context for fast, AOT-friendly (de)serialization.
/// </summary>
[JsonSourceGenerationOptions(
    WriteIndented = false,
    PropertyNameCaseInsensitive = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(Person))]
[JsonSerializable(typeof(Person[]))]
[JsonSerializable(typeof(List<Person>))]
[JsonSerializable(typeof(Address))]
public partial class PersonJsonContext : JsonSerializerContext
{
}

internal static class PersonExtensions
{
    public static string FullName(this Person p) =>
        string.IsNullOrWhiteSpace(p.MiddleName)
            ? $"{p.FirstName} {p.LastName}"
            : $"{p.FirstName} {p.MiddleName} {p.LastName}";
}
