$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$files = @(& git -C $projectRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate Git source files.' }
$issues = @()
foreach ($relative in $files) {
  $path = Join-Path $projectRoot $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
  if ($relative -match '(^|/)(\.godot|artifacts|build|release|export_templates|third_party|ue_export)/' -or
      $relative -match '\.(exe|pck|fbx|uasset|tga|zip|dll|pdb|log|tmp)$') {
    $issues += "Unexpected source payload: $relative"
  }
  if ((Get-Item -LiteralPath $path).Length -gt 5MB) { $issues += "Review large file: $relative" }
  if ($relative -match '\.(gd|tscn|tres|godot|cfg|gdshader)$') {
    $text = Get-Content -LiteralPath $path -Raw
    if ($relative -match '^(scripts|scenes|resources|assets)/' -and
        $text -match 'epic_templates|epic_models|create_manny|res://assets/third_party') {
      $issues += "Removed asset dependency: $relative"
    }
    if ($text -match '(?<![A-Za-z])[A-Za-z]:[\\/][^/]') { $issues += "Absolute local path: $relative" }
    if ($text -match '-----BEGIN (RSA |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}') {
      $issues += "Potential credential: $relative"
    }
    foreach ($match in [regex]::Matches($text, '(?:preload|load)\("res://([^"]+)"\)')) {
      if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $match.Groups[1].Value))) {
        $issues += "Missing static resource: $relative -> $($match.Groups[1].Value)"
      }
    }
  }
}
foreach ($required in @('LICENSE','THIRD_PARTY_NOTICES.md','assets/editor/icons/LICENSE','project.godot')) {
  if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $required))) { $issues += "Missing $required" }
}
if ($issues.Count) { $issues | Write-Output; throw "$($issues.Count) source audit issue(s)" }
Write-Output "SOURCE_AUDIT_OK files=$($files.Count)"
Write-Output 'Heuristic checks only; review external contributions and Git diffs before publishing.'
