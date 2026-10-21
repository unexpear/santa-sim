param([switch]$Anim)
$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
if (Test-Path "$env:USERPROFILE\anim_patch.tar") { Move-Item "$env:USERPROFILE\anim_patch.tar" .tools\anim_patch.tar -Force; tar -xf .tools\anim_patch.tar; Remove-Item .tools\anim_patch.tar }
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
"=== import ==="; & $g --headless --path . --import 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN" | Select -First 20 | % { $_.Line }
"=== quit-after 300 ==="; & $g --headless --path . --quit-after 300 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN|at: " | Select -First 20 | % { $_.Line }
"=== selftest ==="; & $g --headless --path . --fixed-fps 60 -- --selftest 2>&1 | Out-File -Encoding utf8 .tools\selftest_after.txt
Get-Content .tools\selftest_after.txt | Select-String -Pattern "ERROR|WARN|at: " | Select -First 20 | % { $_.Line }
"=== selftest diff vs before (empty = identical) ==="
Compare-Object (Get-Content .tools\selftest_before.txt) (Get-Content .tools\selftest_after.txt) | Out-String
if ($Anim) {
  "=== animcheck (real window) ==="
  $p = Start-Process $g -ArgumentList '--path','D:\dev\santa-sim','--','--animcheck=D:/dev/santa-sim/screenshots' -NoNewWindow -PassThru -RedirectStandardOutput .tools\anim.log -RedirectStandardError .tools\anim.err
  if (-not $p.WaitForExit(120000)) { $p.Kill(); "KILLED" }
  Get-Content .tools\anim.log | Select-String -Pattern "animcheck|ERROR|WARN|at: " | % { $_.Line }
  Get-Content .tools\anim.err | Select -First 20
}
if ($Anim) {
  Remove-Item .tools\anim_out.zip -ErrorAction SilentlyContinue
  Compress-Archive -Path screenshots\anim_*.png, screenshots\anim_frames -DestinationPath .tools\anim_out.zip
  "BEGIN"; [Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\dev\santa-sim\.tools\anim_out.zip')); "END"
}
