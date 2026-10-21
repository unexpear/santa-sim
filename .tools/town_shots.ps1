$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
if (Test-Path "$env:USERPROFILE\town_pkg.tar") { Move-Item "$env:USERPROFILE\town_pkg.tar" .tools\town_pkg.tar -Force; tar -xf .tools\town_pkg.tar; Remove-Item .tools\town_pkg.tar }
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
"=== import ==="; & $g --headless --path . --import 2>&1 | Select-String -Pattern "ERROR|SCRIPT" | Out-String
"=== shots ==="
$p = Start-Process $g -ArgumentList '--path','D:\dev\santa-sim','scenes/town/town.tscn','--','--townshots=D:/dev/santa-sim/screenshots' -NoNewWindow -PassThru -RedirectStandardOutput .tools\townshot.log -RedirectStandardError .tools\townshot.err
if (-not $p.WaitForExit(120000)) { $p.Kill(); "KILLED" }
Get-Content .tools\townshot.log | Select-String -Pattern "town\]|townshots|ERROR|SCRIPT"
Get-Content .tools\townshot.err | Select-String -Pattern "ERROR|SCRIPT"
if ($args -contains 'fps') {
  "=== fps ==="
  $p = Start-Process $g -ArgumentList '--path','D:\dev\santa-sim','scenes/town/town.tscn','--','--townfps' -NoNewWindow -PassThru -RedirectStandardOutput .tools\townfps.log -RedirectStandardError .tools\townfps.err
  if (-not $p.WaitForExit(120000)) { $p.Kill(); "KILLED" }
  Get-Content .tools\townfps.log | Select-String -Pattern "townfps|ERROR|SCRIPT"
}
Add-Type -AssemblyName System.Drawing
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 88L
$names = 'town_topdown','town_street','town_fly','town_overview'
foreach ($n in $names) { $src = [System.Drawing.Image]::FromFile("D:\dev\santa-sim\screenshots\$n.png"); $src.Save("$env:TEMP\$n.jpg", $codec, $ep); $src.Dispose() }
Push-Location $env:TEMP; tar -cf town_jpgs.tar ($names | % { "$_.jpg" }); Pop-Location
