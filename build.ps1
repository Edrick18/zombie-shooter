# Baut die EXE des Spiels neu: build\ZombieShooter.exe (eine einzelne Datei, Spieldaten sind eingebettet).
#   .\build.ps1          -> EXE bauen
#   .\build.ps1 -Run     -> EXE bauen und danach starten
# Der Knopf dazu ist "EXE bauen.bat" (Doppelklick).
#
# Voraussetzung: Godot 4.7 samt Export-Vorlagen (Editor: Editor -> Exportvorlagen verwalten).
# Godot-Pfad: Umgebungsvariable GODOT_EXE, sonst der Standardpfad unten.
# Die Export-Einstellung "Windows Desktop" steht in export_presets.cfg.

param([switch]$Run)

$ErrorActionPreference = "Continue"
$proj = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $proj "build"
$exe = Join-Path $buildDir "ZombieShooter.exe"
$log = Join-Path $buildDir "build_log.txt"

$godot = $env:GODOT_EXE
if (-not $godot) {
    $godot = "$env:USERPROFILE\Downloads\Godot_v4.7\Godot_v4.7-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Host "Godot nicht gefunden: $godot" -ForegroundColor Red
    Write-Host "Setze die Umgebungsvariable GODOT_EXE auf den Pfad zur Konsolen-Version von Godot 4.7."
    exit 2
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
# .gdignore: Godot soll den Ordner build nicht als Teil des Projekts einlesen.
$gdignore = Join-Path $buildDir ".gdignore"
if (-not (Test-Path $gdignore)) { New-Item -ItemType File -Path $gdignore | Out-Null }

# Alte EXE zuerst löschen. So ist sicher, dass die Datei am Ende wirklich neu ist.
if (Test-Path $exe) {
    try {
        Remove-Item -Path $exe -Force -ErrorAction Stop
    } catch {
        Write-Host "Die alte EXE lässt sich nicht ersetzen. Läuft das Spiel noch? Bitte schließen und erneut bauen." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Baue $exe ..." -ForegroundColor Cyan
$started = Get-Date
$outFile = Join-Path $env:TEMP "zombie_shooter_build_out.txt"
$errFile = Join-Path $env:TEMP "zombie_shooter_build_err.txt"
# Der Projektpfad enthält Leerzeichen, deshalb in Anführungszeichen übergeben.
$godotArgs = @("--headless", "--path", "`"$proj`"", "--export-release", "`"Windows Desktop`"", "`"$exe`"")
$p = Start-Process -FilePath $godot -ArgumentList $godotArgs -NoNewWindow -PassThru -Wait `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$output = @()
if (Test-Path $outFile) { $output += Get-Content $outFile }
if (Test-Path $errFile) { $output += Get-Content $errFile }
$output | Set-Content -Path $log -Encoding utf8

$problems = $output | Where-Object { $_ -match "SCRIPT ERROR|ERROR:" }
$ok = ($p.ExitCode -eq 0) -and (Test-Path $exe) -and (-not $problems)
if (-not $ok) {
    Write-Host "Bau fehlgeschlagen (Godot-Code $($p.ExitCode))." -ForegroundColor Red
    if ($problems) { $problems | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
    if (-not (Test-Path $exe)) { Write-Host "  Es wurde keine EXE erzeugt." -ForegroundColor Red }
    Write-Host "Ganze Ausgabe: $log"
    exit 1
}

$sizeMb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
$seconds = [math]::Round(((Get-Date) - $started).TotalSeconds)
Write-Host "Fertig: $exe ($sizeMb MB, $seconds s)" -ForegroundColor Green

if ($Run) {
    Start-Process -FilePath $exe
    Write-Host "Spiel gestartet."
}
exit 0
