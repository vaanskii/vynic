$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:TEMP ('vynic-pos02a-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $stage -ItemType Directory | Out-Null
Copy-Item '\\Mac\Home\Developer\vynic\.pos02a-stage\provisioning.test.exe' (Join-Path $stage 'provisioning.test.exe')
$log = '\\Mac\Home\Developer\vynic\docs\proofs\POS02_A_PROVISIONING_2026-10-09\windows-native.log'
& (Join-Path $stage 'provisioning.test.exe') '-test.v=true' '-test.run=^TestProduction' '-test.timeout=120s' 2>&1 | Out-File -Encoding utf8 $log
$code = $LASTEXITCODE
@{exitCode=$code; architecture=$env:PROCESSOR_ARCHITECTURE; principal=(& whoami.exe); stage=$stage; serviceInstalled=$false; printerIO=$false} | ConvertTo-Json | Out-File -Encoding utf8 '\\Mac\Home\Developer\vynic\docs\proofs\POS02_A_PROVISIONING_2026-10-09\windows-result.json'
exit $code
