$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$source='\\Mac\Home\Developer\vynic\.print-production-stage'
$work=Join-Path $env:TEMP ('vynic-print-production-storage-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $work -Recurse
$manifest=Get-Content (Join-Path $work 'manifest.json') -Raw | ConvertFrom-Json
foreach($entry in $manifest.PSObject.Properties) {
 $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $work $entry.Name)).Hash.ToLower()
 if($actual -ne $entry.Value) {throw ('hash mismatch: '+$entry.Name)}
}
Set-Location $work
$results=@()
foreach($package in @('printstation','printcluster')) {
 $start=Get-Date
 $regex=if($package -eq 'printcluster'){'^Test(Station|LocalStation|Normalized|ProjectionRollback|EffectiveModes|FullRasterChunking|SnapshotResult)' }else{'^Test'}
 & (Join-Path $work ($package+'.test.exe')) '-test.v' '-test.count=1' ('-test.run='+$regex) ('-test.timeout=180s') 1>($package+'.stdout.log') 2>($package+'.stderr.log')
 $code=$LASTEXITCODE
 $results+=@{package=$package;exitCode=$code;durationSeconds=((Get-Date)-$start).TotalSeconds;regex=$regex}
}
$receipt=@{identity=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name;sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value;architecture=[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();work=$work;results=$results;physicalTests='NOT_RUN';scmTests='NOT_RUN'}
$receipt|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 'windows-result.json'
$destination=Join-Path $source 'results'
New-Item -ItemType Directory -Force -Path $destination|Out-Null
Copy-Item -Path '*.log','windows-result.json' -Destination $destination
$receipt|ConvertTo-Json -Depth 8
if(@($results|Where-Object {$_.exitCode -ne 0}).Count -ne 0){exit 1}
