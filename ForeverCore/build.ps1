param([string]$EngineSource = (Join-Path $PSScriptRoot '..\deps\mythicsim'))
$ErrorActionPreference='Stop'
foreach ($tool in @('git','go','protoc','protoc-gen-go','python')) {
 if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Build-Werkzeug fehlt: $tool" }
}
& python (Join-Path $PSScriptRoot 'build_engine.py') '--engine-source' $EngineSource '--output' (Join-Path $PSScriptRoot 'MythicSim.exe') '--check'
if ($LASTEXITCODE) { throw 'MythicSim-Build/Pruefung fehlgeschlagen.' }
Push-Location $PSScriptRoot
try {
 $previousEngine = $env:FC_TEST_ENGINE
 $env:FC_TEST_ENGINE = Join-Path $PSScriptRoot 'MythicSim.exe'
 & go test '-buildvcs=false' './...'
 if ($LASTEXITCODE) { throw 'ForeverCore-Tests fehlgeschlagen.' }
 & go build '-buildvcs=false' '-trimpath' '-o' 'ForeverCore.exe' './...'
 if ($LASTEXITCODE) { throw 'ForeverCore-Build fehlgeschlagen.' }
} finally { $env:FC_TEST_ENGINE = $previousEngine; Pop-Location }
