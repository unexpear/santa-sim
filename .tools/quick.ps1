Set-Location D:\dev\santa-sim
powershell -ExecutionPolicy Bypass -File .tools\apply.ps1 | Out-Null
$g = ".\.tools\godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --headless --path . --import 2>&1 | Out-String -Stream | Select-String -Pattern "SCRIPT ERROR|Parse Error" | Select -First 10 | % { $_.Line }
"--- quit-after"
& $g --headless --path . --quit-after 200 2>&1 | Out-String -Stream | Select-String -Pattern "ERROR|WARN|at: |night\]" | Select -Unique -First 30 | % { $_.Line }
