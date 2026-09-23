function Assert-ImageBuildDockerCli () {
    <#
    .SYNOPSIS
        Verifies that the docker CLI is available and returns its client version.
    .DESCRIPTION
        The per-distro Image-Build-*.ps1 entry scripts call this once before
        launching any `docker buildx build` invocation. Throws when docker is
        not on PATH.
    .REMARKS
        1. Locate `docker` with Get-Command.
        2. Query `docker version --format '{{.Client.Version}}'`.
        3. Return the trimmed version string.
    #>
    [CmdletBinding()]
    Param ()

    Process {

        $dockerCommand = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
        if (-not $dockerCommand) {
            throw "docker CLI was not found in PATH."
        }

        return (& docker version --format '{{.Client.Version}}').Trim()
    }
}
