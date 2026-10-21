param([string[]]$Runs = @('intcheck','gadgetcheck','fxshots','fpscheck'), [switch]$NoSync, [switch]$NoTests, [string]$Pattern = 'int_*,gadget_*,fx_*')
$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
if (-not $NoSync -and (Test-Path "$env:USERPROFILE\anim_patch.tar")) { Move-Item "$env:USERPROFILE\anim_patch.tar" .tools\anim_patch.tar -Force; tar -xf .tools\anim_patch.tar; Remove-Item .tools\anim_patch.tar; "synced" }
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not $NoTests) {
  "=== import ==="; & $g --headless --path . --import 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN" | Select -First 20 | % { $_.Line }
  "=== quit-after ==="; & $g --headless --path . --quit-after 300 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN|at: res" | Select -First 30 | % { $_.Line }
  "=== selftest ==="; & $g --headless --path . --fixed-fps 60 -- --selftest 2>&1 | Out-File -Encoding utf8 .tools\selftest_after.txt
  Get-Content .tools\selftest_after.txt | Select-String -Pattern "ERROR|WARN|at: res" | % { $_.Line }
  "=== diff (empty = identical) ==="; Compare-Object (Get-Content .tools\selftest_before.txt) (Get-Content .tools\selftest_after.txt) | Out-String
}
New-Item -ItemType Directory -Force screenshots | Out-Null
foreach ($run in $Runs) {
  $arg = if ($run -eq 'fpscheck') { '--fpscheck' } else { "--$run=D:/dev/santa-sim/screenshots" }
  "=== $arg ==="
  $p = Start-Process $g -ArgumentList '--path','D:\dev\santa-sim','--',$arg -NoNewWindow -PassThru -RedirectStandardOutput ".tools\$run.log" -RedirectStandardError ".tools\$run.err"
  if (-not $p.WaitForExit(900000)) { $p.Kill(); "KILLED" }
  Get-Content ".tools\$run.log", ".tools\$run.err" | Select-String -Pattern "ERROR|WARN|at: res|fps\]|FAIL|PASS|NOT reached|evidence|gadget\]" | Select -First 60 | % { $_.Line }
}
foreach ($pat in $Pattern.Split(',')) {
  foreach ($f in Get-ChildItem "screenshots\$pat.jpg") { "BEGIN $($f.BaseName)"; [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName)); "END" }
}
