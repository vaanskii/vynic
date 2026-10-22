param([string]$SourceRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $SourceRoot 'POS02_SOURCE_SHA256.json'
if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'db74149c4680d05e16a3a1f53906b269bf76be3d1d71e78796119633d15ff51a') {
  throw 'Source manifest does not match this one-shot runner candidate.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$count = 0
foreach ($entry in $manifest.PSObject.Properties) {
  $file = Join-Path $SourceRoot ($entry.Name -replace '/', [IO.Path]::DirectorySeparatorChar)
  if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing source: $($entry.Name)" }
  if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw "Source mismatch: $($entry.Name)" }
  $count++
}
if ($count -ne 883) { throw 'Unexpected source count.' }
Write-Output "PASS: $count one-shot runner candidate source files. No app, tests, VM or printer action performed."
