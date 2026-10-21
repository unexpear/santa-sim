param([string[]]$Shots = @('landing_test','models_closeup','models_side'))
$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
if (Test-Path "$env:USERPROFILE\santa-src.tar") { Move-Item "$env:USERPROFILE\santa-src.tar" .tools\santa-src.tar -Force; tar -xf .tools\santa-src.tar; Remove-Item .tools\santa-src.tar }
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
"=== import ==="; & $g --headless --path . --import 2>&1 | Select-String -Pattern "ERROR|WARN|SCRIPT" | Out-String
"=== quit-after 300 ==="; & $g --headless --path . --quit-after 300 2>&1 | Out-String
"=== selftest ==="; & $g --headless --path . --fixed-fps 60 -- --selftest 2>&1 | Out-String
"=== shots ==="
$p = Start-Process $g -ArgumentList '--path','D:\dev\santa-sim','--','--screenshot=D:/dev/santa-sim/screenshots' -NoNewWindow -PassThru -RedirectStandardOutput .tools\shot.log -RedirectStandardError .tools\shot.err
if (-not $p.WaitForExit(90000)) { $p.Kill(); "KILLED" }
Get-Content .tools\shot.log, .tools\shot.err
Add-Type -AssemblyName System.Drawing
foreach ($n in $Shots) { $src = [System.Drawing.Image]::FromFile("D:\dev\santa-sim\screenshots\$n.png"); $bmp = New-Object System.Drawing.Bitmap 1280,720; $gr = [System.Drawing.Graphics]::FromImage($bmp); $gr.InterpolationMode='HighQualityBicubic'; $gr.DrawImage($src,0,0,1280,720); $ms = New-Object IO.MemoryStream; $bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Jpeg); "BEGIN $n"; [Convert]::ToBase64String($ms.ToArray()); "END $n"; $gr.Dispose(); $bmp.Dispose(); $src.Dispose() }