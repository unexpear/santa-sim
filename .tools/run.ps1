param([string[]]$Runs = @('firevis'), [string]$Tag = 'base', [string[]]$Extra = @())
$ErrorActionPreference = 'Continue'
Set-Location D:\dev\santa-sim
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$out = ".tools\runs\$Tag"; New-Item -ItemType Directory -Force $out | Out-Null
$shots = "D:/dev/santa-sim/.tools/runs/$Tag/shots"; New-Item -ItemType Directory -Force $shots | Out-Null
"=== import ==="; & $g --headless --path . --import 2>&1 | Out-String -Stream | Select-String -Pattern "SCRIPT ERROR|Parse Error|ERROR" | Select -First 20 | % { $_.Line }
$Runs = $Runs -join "," -split ","; foreach ($run in $Runs) {
  # only a visible Godot (the designer playing) blocks a windowed run; headless workers don't
  $live = @(Get-CimInstance Win32_Process | ? { $_.Name -match 'godot' -and $_.CommandLine -notmatch '--headless' })
  if ($live.Count -gt 0) { "SKIP $run : a Godot window is already running (pid $($live.ProcessId -join ','))"; continue }
  $arg = if ($run -in @('fpscheck','selftest')) { "--$run" } else { "--$run=$shots" }
  $al = @('--path','D:\dev\santa-sim','--',$arg) + $Extra
  if ($run -eq 'selftest') { $al = @('--headless','--path','D:\dev\santa-sim','--fixed-fps','60','--',$arg) }
  "=== $arg $Extra ==="
  $p = Start-Process $g -ArgumentList $al -NoNewWindow -PassThru -RedirectStandardOutput "$out\$run.log" -RedirectStandardError "$out\$run.err"
  if (-not $p.WaitForExit(900000)) { $p.Kill(); "KILLED" }
  Get-Content "$out\$run.log", "$out\$run.err" | Select-String -Pattern "SCRIPT ERROR|Parse Error|ERROR|at: res|fps\]|FAIL|PASS|NOT |bump\]|solid\]|rope\]|deco\]|wall\]|fire\]|flue|probe|carve\]|chimvis\]|chimtop\]|mech\]|night\]" | Select -First 80 | % { $_.Line }
}
