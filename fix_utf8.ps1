$ErrorActionPreference = "Stop"

$root = Get-Location
$exts = @("*.dart","*.yaml","*.yml","*.arb","*.json","*.md","*.txt")

$ignore = @("\build\","\android\build\","\ios\Pods\","\.dart_tool\","\.git\","\.idea\","\.vscode\")

function Ignore($p) {
  $l = $p.ToLower()
  foreach ($i in $ignore) { if ($l.Contains($i)) { return $true } }
  return $false
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$files = @()
foreach ($e in $exts) {
  $files += Get-ChildItem -Path $root -Recurse -File -Filter $e -ErrorAction SilentlyContinue
}

$converted = 0
foreach ($f in $files) {
  if (Ignore($f.FullName)) { continue }

  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $tUtf8  = [System.Text.Encoding]::UTF8.GetString($bytes)
  $tLatin = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($bytes)

  $badUtf8  = ($tUtf8.ToCharArray()  | Where-Object { $_ -eq [char]0xFFFD }).Count
  $badLatin = ($tLatin.ToCharArray() | Where-Object { $_ -eq [char]0xFFFD }).Count

  $final = if ($badUtf8 -gt $badLatin) { $tLatin } else { $tUtf8 }

  $bak = $f.FullName + ".bak"
  if (-not (Test-Path $bak)) { Copy-Item $f.FullName $bak }

  [System.IO.File]::WriteAllText($f.FullName, $final, $utf8NoBom)
  $converted++
}

Write-Host "✅ Convertidos para UTF-8 (sem BOM): $converted arquivos"

Write-Host "🔎 Procurando caractere '�'..."
$hits = 0
foreach ($e in $exts) {
  Get-ChildItem -Path $root -Recurse -File -Filter $e -ErrorAction SilentlyContinue | ForEach-Object {
    if (Ignore($_.FullName)) { return }
    $t = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -ne $t -and $t.Contains("�")) { $hits++; Write-Host " - $($_.FullName)" }
  }
}
if ($hits -eq 0) { Write-Host "Nenhum '�' encontrado ✅" }
