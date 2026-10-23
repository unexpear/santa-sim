# Apply the box patch safely: back up the files it overwrites, extract, headless parse check,
# and roll back automatically if anything fails to compile (so a launch never gets a broken tree).
Set-Location D:\dev\santa-sim
$tar = "$env:USERPROFILE\santa-patch.tar"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$bk = ".tools\backups\apply_$ts"; New-Item -ItemType Directory -Force $bk | Out-Null
$files = tar -tf $tar | ? { $_ -notmatch '/$' } | % { $_ -replace '^\./','' }
foreach ($f in $files) { if (Test-Path $f) { $d = Join-Path $bk (Split-Path $f); New-Item -ItemType Directory -Force $d | Out-Null; Copy-Item $f $d -Force } }
tar -xf $tar -C .
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$errs = & $g --headless --path . --quit-after 90 2>&1 | Out-String -Stream | Select-String "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script"
$errs += foreach ($s in ($files | ? { $_ -like '*.gd' -and $_ -notlike '*review_tree*' })) { & $g --headless --path . --check-only --script "res://$s" 2>&1 | Out-String -Stream | Select-String "SCRIPT ERROR|Parse Error" }
if ($errs) {
  "ROLLBACK: errors after apply:"; $errs | select -first 10 | % { $_.Line }
  foreach ($f in $files) { $b = Join-Path $bk $f; if (Test-Path $b) { Copy-Item $b $f -Force } elseif ($f -like '*.gd' -or $f -like '*.gdshader') { Remove-Item $f -Force -ea 0 } }
} else { "APPLIED OK ($($files.Count) files)" }
