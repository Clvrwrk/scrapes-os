[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupMemory = Join-Path $ScriptDir "setup-memory.ps1"

Write-Host "setup-memsearch.ps1 is kept for compatibility."
Write-Host "Using the recommended setup-memory.ps1 flow instead."
Write-Host ""

& $SetupMemory @RemainingArgs
exit $LASTEXITCODE
