# (fixed) Restores README/GADGETS and the DESIGN.md recovery stub from .tools\docfix (UTF-8, no BOM).
$root = "D:\dev\santa-sim"
$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($n in @('README.md','GADGETS.md','DESIGN.md')) {
  $src = Join-Path $root ".tools\docfix\$n"
  $dst = Join-Path $root $n
  if ((Test-Path $src) -and ((Get-Item $dst).Length -eq 0)) { [IO.File]::WriteAllText($dst, [IO.File]::ReadAllText($src, [Text.Encoding]::UTF8), $enc); "$n restored ($((Get-Item $dst).Length) bytes)" } else { "$n left alone" }
}
