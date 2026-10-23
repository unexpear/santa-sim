param([string]$Proj = 'D:\dev\santa-sim', [string]$Tag = 'rv_after')
Set-Location D:\dev\santa-sim
$g = "D:\dev\santa-sim\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$live = Get-Process | ? { $_.ProcessName -match 'godot' }
if ($live) { "SKIP: Godot already running"; exit }
$out = "D:\dev\santa-sim\.tools\runs\$Tag"; New-Item -ItemType Directory -Force "$out\shots" | Out-Null
$env:REVIEW_DIR = "$out\shots" -replace '\\','/'
& $g --headless --path $Proj --import 2>&1 | Out-Null
$p = Start-Process $g -ArgumentList @('--path',$Proj,'--script','res://scripts/review_tree.gd') -NoNewWindow -PassThru -RedirectStandardOutput "$out\review.log" -RedirectStandardError "$out\review.err"
if (-not $p.WaitForExit(600000)) { $p.Kill(); "KILLED" }
Get-Content "$out\review.log","$out\review.err" | Select-String "review\]|still|SCRIPT ERROR|at: res" | select -first 60 | % Line
