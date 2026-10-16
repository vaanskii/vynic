$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:TEMP ('vynic-pos02b-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $stage -ItemType Directory | Out-Null
$source = '\\Mac\Home\Developer\vynic\.pos02b-stage\peer.test.exe'
$binary = Join-Path $stage 'peer.test.exe'
Copy-Item $source $binary
$expected=(Get-FileHash $source -Algorithm SHA256).Hash
$actual=(Get-FileHash $binary -Algorithm SHA256).Hash
if($actual -ne $expected){ throw 'binary hash mismatch' }
$root='\\Mac\Home\Developer\vynic\docs\proofs\POS02_B_2026-10-09'
& $binary '-test.v=true' '-test.run=^TestPeerProcess' '-test.timeout=6m' 2>&1 | Out-File -Encoding utf8 (Join-Path $root 'windows-native.log')
$code = $LASTEXITCODE
@{exitCode=$code; architecture=$env:PROCESSOR_ARCHITECTURE; principal=(& whoami.exe); stage=$stage; sha256=$actual; serviceInstalled=$false; printerIO=$false} | ConvertTo-Json | Out-File -Encoding utf8 (Join-Path $root 'windows-result.json')
exit $code
