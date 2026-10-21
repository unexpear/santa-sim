$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
if (Test-Path "$env:USERPROFILE\anim_patch.tar") { Move-Item "$env:USERPROFILE\anim_patch.tar" .tools\anim_patch.tar -Force; tar -xf .tools\anim_patch.tar; Remove-Item .tools\anim_patch.tar }
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
"=== import ==="; & $g --headless --path . --import 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN" | Select -First 20 | % { $_.Line }
"=== quit-after ==="; & $g --headless --path . --quit-after 300 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN|at: res" | Select -First 20 | % { $_.Line }
"=== selftest ==="; & $g --headless --path . --fixed-fps 60 -- --selftest 2>&1 | Out-File -Encoding utf8 .tools\selftest_after.txt
Get-Content .tools\selftest_after.txt | Select-String -Pattern "ERROR|WARN|at: res" | % { $_.Line }
"=== diff (empty = identical) ==="; Compare-Object (Get-Content .tools\selftest_before.txt) (Get-Content .tools\selftest_after.txt) | Out-String
"=== headlight shots ==="
$p = Start-Process $g -ArgumentList '--path','D:\dev\santa-sim','--','--headlight=D:/dev/santa-sim/screenshots' -NoNewWindow -PassThru -RedirectStandardOutput .tools\hl.log -RedirectStandardError .tools\hl.err
if (-not $p.WaitForExit(90000)) { $p.Kill(); "KILLED" }
Get-Content .tools\hl.log, .tools\hl.err | Select-String -Pattern "ERROR|WARN|at: res|animcheck|headlight\]" | % { $_.Line }
Add-Type -AssemblyName System.Drawing
foreach ($f in Get-ChildItem screenshots\headlight_*.png) { $src = [System.Drawing.Image]::FromFile($f.FullName); $bmp = New-Object System.Drawing.Bitmap 1280,720; $gr = [System.Drawing.Graphics]::FromImage($bmp); $gr.InterpolationMode='HighQualityBicubic'; $gr.DrawImage($src,0,0,1280,720); $ms = New-Object IO.MemoryStream; $bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Jpeg); "BEGIN $($f.BaseName)"; [Convert]::ToBase64String($ms.ToArray()); "END"; $gr.Dispose(); $bmp.Dispose(); $src.Dispose() }
