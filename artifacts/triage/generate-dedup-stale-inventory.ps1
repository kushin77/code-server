$ErrorActionPreference = 'Stop'
Set-Location 'C:\code-server-enterprise'

$targets = @('scripts', 'docs', 'config', '.github/workflows')
$files = Get-ChildItem $targets -Recurse -File -ErrorAction SilentlyContinue

$records = foreach ($f in $files) {
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName
  [PSCustomObject]@{
    path = $f.FullName.Substring((Get-Location).Path.Length + 1).Replace('\\', '/')
    size = [int64]$f.Length
    sha256 = $h.Hash.ToLowerInvariant()
  }
}

$dupes = $records |
  Group-Object sha256 |
  Where-Object { $_.Count -gt 1 } |
  ForEach-Object {
    [PSCustomObject]@{
      sha256 = $_.Name
      fileCount = $_.Count
      size = ($_.Group | Select-Object -First 1).size
      paths = ($_.Group | Sort-Object path | Select-Object -ExpandProperty path)
      disposition = 'keep_one_remove_duplicates'
      owner = 'Platform Engineering'
    }
  }

$deprMarkers = @('deprecated', 'obsolete', 'legacy shim', 'do not use', 'compatibility only')
$stale = foreach ($f in $files) {
  $p = $f.FullName.Substring((Get-Location).Path.Length + 1).Replace('\\', '/')

  if (
    $p -match '(^|/)deprecated(/|$)' -or
    $p -match '(^|/)archive(/|$)' -or
    $p -match '(^|/)_archive(/|$)' -or
    $p -match '^\.archived/'
  ) {
    [PSCustomObject]@{
      path = $p
      reason = 'archived_or_deprecated_path'
      disposition = 'archive'
      owner = 'Platform Engineering'
    }
    continue
  }

  try {
    $head = (Get-Content -LiteralPath $f.FullName -TotalCount 80 -ErrorAction Stop | Out-String).ToLowerInvariant()
    foreach ($m in $deprMarkers) {
      if ($head.Contains($m)) {
        [PSCustomObject]@{
          path = $p
          reason = "marker:$m"
          disposition = 'remove_or_migrate'
          owner = 'Platform Engineering'
        }
        break
      }
    }
  }
  catch {
  }
}

$stale = $stale | Sort-Object path -Unique

New-Item -ItemType Directory -Force 'artifacts/triage' | Out-Null

$result = [PSCustomObject]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  scope = $targets
  duplicateGroups = $dupes
  duplicateGroupCount = @($dupes).Count
  staleComponents = $stale
  staleComponentCount = @($stale).Count
}

$result | ConvertTo-Json -Depth 9 | Set-Content -Encoding UTF8 'artifacts/triage/dedup-stale-inventory.json'

$md = @()
$md += '# Dedup And Stale Inventory'
$md += ''
$md += ('Generated at (UTC): ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))
$md += ('Duplicate groups: ' + @($dupes).Count)
$md += ('Stale components: ' + @($stale).Count)
$md += ''
$md += '## Duplicate Groups'
$md += ''
if (@($dupes).Count -eq 0) {
  $md += '- None detected in current scan scope.'
} else {
  foreach ($d in $dupes | Select-Object -First 20) {
    $md += ('- sha256=' + $d.sha256 + ' files=' + $d.fileCount + ' size=' + $d.size)
    foreach ($path in $d.paths) {
      $md += ('  - ' + $path)
    }
  }
}
$md += ''
$md += '## Stale Components'
$md += ''
if (@($stale).Count -eq 0) {
  $md += '- None detected in current scan scope.'
} else {
  foreach ($s in $stale | Select-Object -First 50) {
    $md += ('- ' + $s.path + ' | reason=' + $s.reason + ' | disposition=' + $s.disposition + ' | owner=' + $s.owner)
  }
}
$md += ''
$md += 'Machine-readable artifact: artifacts/triage/dedup-stale-inventory.json'

$md | Set-Content -Encoding UTF8 'artifacts/triage/dedup-stale-inventory.md'

Write-Output ('duplicate_groups=' + @($dupes).Count + ' stale_components=' + @($stale).Count)
