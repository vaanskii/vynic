param([string]$SourceRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $SourceRoot 'POS02_SOURCE_SHA256.json'
if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'd194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8') {
  throw 'Source manifest does not match this revised candidate.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$count = 0
foreach ($entry in $manifest.PSObject.Properties) {
  $file = Join-Path $SourceRoot ($entry.Name -replace '/', [IO.Path]::DirectorySeparatorChar)
  if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing source: $($entry.Name)" }
  if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw "Source mismatch: $($entry.Name)" }
  $count++
}
if ($count -ne 876) { throw 'Unexpected source count.' }
Write-Output "PASS: $count revised candidate source files. No app, tests, VM or printer action performed."
