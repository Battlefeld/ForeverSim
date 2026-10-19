param([string]$Addons)
$ErrorActionPreference = 'Stop'
if (-not $Addons) { $Addons = Read-Host 'Vollstaendiger Pfad zu WoW\Interface\AddOns' }
$Addons = [IO.Path]::GetFullPath($Addons.Trim('"'))
if (Get-Process -Name 'Wow','WowClassic','WowClassicB','WowB' -ErrorAction SilentlyContinue) { throw 'WoW vor der Installation vollstaendig schliessen.' }
$base=$PSScriptRoot
$names=@('ForeverSimBridge','ForeverCoreBridge')
foreach ($name in $names) {
 $src=Join-Path $base ('AddOns\'+$name)
 if (-not (Test-Path -LiteralPath (Join-Path $src ($name+'.toc')))) { throw "Unvollstaendiges Paket: $name" }
}
foreach ($name in @('ForeverCore.exe','MythicSim.exe','Lua.exe','engine.lock.json')) {
 if (-not (Test-Path -LiteralPath (Join-Path $base $name))) { throw "Paketdatei fehlt: $name" }
}
$backup=Join-Path $base ('Backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
New-Item -ItemType Directory -Path $Addons -Force | Out-Null
foreach ($name in $names) {
 $dest=Join-Path $Addons $name
 if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination $backup -Recurse;Remove-Item -LiteralPath $dest -Recurse -Force }
 Copy-Item -LiteralPath (Join-Path $base ('AddOns\'+$name)) -Destination $Addons -Recurse
}
$utf8=New-Object System.Text.UTF8Encoding($false)
for ($i=1;$i -le 2048;$i++) {
 $name='FC3_S{0:D4}' -f $i;$dir=Join-Path $Addons $name
 New-Item -ItemType Directory -Path $dir -Force | Out-Null
 [IO.File]::WriteAllText((Join-Path $dir ($name+'.toc')), "## Interface: 16001`n## Title: ForeverCore Antwort $i`n## LoadOnDemand: 1`n## Dependencies: ForeverCoreBridge`nInbox.lua`n",$utf8)
 [IO.File]::WriteAllText((Join-Path $dir 'Inbox.lua'),"ForeverCore_Reply=nil`n",$utf8)
}
$lock=Get-Content -LiteralPath (Join-Path $base 'engine.lock.json') -Raw | ConvertFrom-Json
$config=@{addons=$Addons;engine='MythicSim.exe';engineRevision=$lock.buildIdentity;runtime='Runtime';data='Data';lua='Lua.exe';autoSync=$false}
[IO.File]::WriteAllText((Join-Path $base 'config.json'),($config | ConvertTo-Json),$utf8)
[IO.File]::WriteAllText((Join-Path $base 'last-backup.txt'),$backup,$utf8)
Write-Host 'Installiert. ForeverCore.exe starten, dann WoW. In WoW: /fc ping, /fc on, /fc sim.'
Write-Host 'Alte MiniLab-/FSBridgeTest-Addons und ein altes ForeverDungeonQuest deaktivieren. SavedVariables werden nicht veraendert.'
foreach ($old in @('ForeverDungeonQuest','ForeverDungeonQuestRoutes60')) { if (Test-Path -LiteralPath (Join-Path $Addons $old)) { Write-Host "Hinweis: $old liegt noch im AddOns-Ordner (wird nicht angefasst, gehoert nicht mehr zum Paket)." } }
Write-Host "Sicherung: $backup"
