param([string]$Addons)
$ErrorActionPreference='Stop'
if (Get-Process -Name 'Wow','WowClassic','WowClassicB','WowB' -ErrorAction SilentlyContinue) { throw 'WoW zuerst schliessen.' }
if (-not $Addons) { $cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json;$Addons=$cfg.addons }
$backup=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'last-backup.txt')).Trim()
if (-not (Test-Path -LiteralPath $backup)) { throw 'Sicherung fehlt.' }
foreach ($name in @('ForeverDungeonQuest','ForeverDungeonQuestRoutes60','ForeverSimBridge','ForeverCoreBridge')) {
 $src=Join-Path $backup $name;$dest=Join-Path $Addons $name
 if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
 if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $Addons -Recurse }
}
Write-Host 'Vorherige Addonordner wiederhergestellt; SavedVariables bleiben erhalten.'
