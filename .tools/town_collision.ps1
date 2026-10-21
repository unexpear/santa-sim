# Collision + decorations pass for the town scene: FPS without/with the full collision, the collision checks, and the C-key debug shot.
$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
if (Test-Path "$env:USERPROFILE\town_pkg.tar") { Move-Item "$env:USERPROFILE\town_pkg.tar" .tools\town_pkg.tar -Force; tar -xf .tools\town_pkg.tar; Remove-Item .tools\town_pkg.tar }
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
"=== import ==="; & $g --headless --path . --import 2>&1 | Select-String -Pattern "ERROR|SCRIPT" | Out-String
function Run($label, $extra, $pat) {
  "=== $label ==="
  $a = @('--path','D:\dev\santa-sim','scenes/town/town.tscn','--') + $extra
  $p = Start-Process $g -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput .tools\tc.log -RedirectStandardError .tools\tc.err
  if (-not $p.WaitForExit(150000)) { $p.Kill(); "KILLED" }
  Get-Content .tools\tc.log | Select-String -Pattern $pat
  Get-Content .tools\tc.err | Select-String -Pattern "ERROR|SCRIPT"
}
Run 'fps: old hulls, no decorations' @('--townfps','--nocollide','--nodeco') 'townfps|collision:|ERROR|SCRIPT'
Run 'fps: full collision, no decorations' @('--townfps','--nodeco') 'townfps|collision:|ERROR|SCRIPT'
Run 'fps: full collision + decorations' @('--townfps') 'townfps|collision:|decorations:|ERROR|SCRIPT'
Run 'collision checks' @('--towncollide') 'RESULT|PASS|FAIL|ERROR|SCRIPT'
Run 'debug shot' @('--colshot=D:/dev/santa-sim/screenshots/town_collision_debug.png') 'townshots|ERROR|SCRIPT'
Run 'deco shot' @('--decoshot=D:/dev/santa-sim/screenshots/town_deco.png') 'townshots|ERROR|SCRIPT'
Add-Type -AssemblyName System.Drawing
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 88L
foreach ($n in 'town_collision_debug','town_deco') { $src = [System.Drawing.Image]::FromFile("D:\dev\santa-sim\screenshots\$n.png"); $src.Save("$env:TEMP\$n.jpg", $codec, $ep); $src.Dispose() }
