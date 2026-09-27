param(
  [ValidateSet('play', 'editor', 'test', 'export')]
  [string]$Task = 'play',
  [string]$Godot = $env:GODOT,
  [string[]]$Tests = @('run_tests','bot_appearance','player_features','trainer_settings',
    'simulation_scoring','sniper_duel','sniper_scope','scope_optics','reticle_editor',
    'shot_review_visuals','map_roundtrip','smooth_stairs')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
  foreach ($candidate in @('godot', 'godot4')) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) { $Godot = $command.Source; break }
  }
}
if (-not $Godot) { throw 'Set GODOT or pass -Godot with the Godot console executable path.' }
New-Item -ItemType Directory -Path "$projectRoot/artifacts" -Force | Out-Null
function Invoke-Godot([string[]]$Arguments, [string]$Log) {
  & $Godot --path $projectRoot --log-file $Log @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Godot failed ($LASTEXITCODE); see $Log" }
  if (Select-String -LiteralPath $Log -Pattern 'SCRIPT ERROR|ERROR:|FAIL[: ]' -Quiet) {
    throw "Godot reported errors; see $Log"
  }
}
switch ($Task) {
  'play' { & $Godot --path $projectRoot }
  'editor' { & $Godot --editor --path $projectRoot }
  'test' {
    Invoke-Godot @('--headless','--editor','--quit') "$projectRoot/artifacts/import.log"
    foreach ($test in $Tests) {
      if ($test -notmatch '^[a-z_]+$' -or -not (Test-Path "$projectRoot/tests/$test.gd")) {
        throw "Unknown test: $test"
      }
      Invoke-Godot @('--headless','--script',"res://tests/$test.gd",'--fixed-fps','120','--','--integration') "$projectRoot/artifacts/$test.log"
    }
  }
  'export' {
    New-Item -ItemType Directory -Path "$projectRoot/build" -Force | Out-Null
    Invoke-Godot @('--headless','--editor','--quit') "$projectRoot/artifacts/import.log"
    Invoke-Godot @('--headless','--export-release','Nacl Windows',"$projectRoot/build/NaclAimTrainingTool.exe") "$projectRoot/artifacts/export.log"
    Invoke-Godot @('--headless','--script','res://tools/engine-licenses.gd') "$projectRoot/artifacts/licenses.log"
    Copy-Item -LiteralPath "$projectRoot/LICENSE","$projectRoot/THIRD_PARTY_NOTICES.md" -Destination "$projectRoot/build"
    Copy-Item -LiteralPath "$projectRoot/assets/editor/icons/LICENSE" -Destination "$projectRoot/build/LUCIDE_LICENSE.txt"
  }
}
