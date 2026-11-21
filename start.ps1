# Startet das Projekt.
#   .\start.ps1           -> Godot-Editor mit dem Projekt
#   .\start.ps1 -Game     -> Spielfenster mit der Hauptszene (ohne Editor)
#
# Pfad: Umgebungsvariable GODOT_GUI (Fenster-Version von Godot 4.7), sonst der Standardpfad unten.

param([switch]$Game)

$proj = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotGui = if ($env:GODOT_GUI) { $env:GODOT_GUI } else { "$env:USERPROFILE\Downloads\Godot_v4.7\Godot_v4.7-stable_win64.exe" }

if (-not (Test-Path $godotGui)) {
    Write-Host "Godot nicht gefunden: $godotGui" -ForegroundColor Red
    Write-Host "Setze die Umgebungsvariable GODOT_GUI auf den Pfad zur Fenster-Version von Godot 4.7."
    exit 2
}

# Der Projektpfad enthält Leerzeichen, deshalb in Anführungszeichen übergeben.
if ($Game) {
    Start-Process -FilePath $godotGui -ArgumentList @("--path", "`"$proj`"")
    Write-Host "Spielfenster gestartet."
} else {
    Start-Process -FilePath $godotGui -ArgumentList @("--path", "`"$proj`"", "--editor")
    Write-Host "Editor gestartet."
}
