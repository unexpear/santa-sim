Set-Location D:\dev\santa-sim
if (Test-Path "$env:USERPROFILE\santa-patch.tar") { Move-Item "$env:USERPROFILE\santa-patch.tar" .tools\santa-patch.tar -Force; tar -xf .tools\santa-patch.tar; Remove-Item .tools\santa-patch.tar; "applied" } else { "no patch" }
git status --short
