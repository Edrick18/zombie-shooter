# Führt die Skriptprüfung (tests\check_scripts.gd) und danach alle Tests (tests\test_*.gd) headless aus.
# Ein Lauf gilt nur als bestanden, wenn Godot mit Code 0 endet UND die Ausgabe
# keine Skriptfehler (SCRIPT ERROR, ERROR:) und keine FEHLER-Meldungen enthält.
# Jede Datei hat ein Zeitlimit; hängt sie, wird Godot beendet und sie gilt als fehlgeschlagen.
#
# Godot-Pfad: Umgebungsvariable GODOT_EXE, sonst der Standardpfad unten.

$ErrorActionPreference = "Continue"
$timeoutSeconds = 120
$proj = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = $env:GODOT_EXE
if (-not $godot) {
    $godot = "$env:USERPROFILE\Downloads\Godot_v4.7\Godot_v4.7-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Host "Godot nicht gefunden: $godot" -ForegroundColor Red
    Write-Host "Setze die Umgebungsvariable GODOT_EXE auf den Pfad zur Konsolen-Version von Godot 4.7."
    exit 2
}

# Zuerst die Skriptprüfung, dann die Tests in alphabetischer Reihenfolge.
$names = @("check_scripts.gd")
$names += Get-ChildItem -Path (Join-Path $proj "tests") -Filter "test_*.gd" | Sort-Object Name | ForEach-Object { $_.Name }
$failed = @()
$outFile = Join-Path $env:TEMP "zombie_shooter_test_out.txt"
$errFile = Join-Path $env:TEMP "zombie_shooter_test_err.txt"

foreach ($name in $names) {
    Write-Host "== $name" -ForegroundColor Cyan
    $godotArgs = @("--headless", "--path", "`"$proj`"", "-s", "res://tests/$name")
    $p = Start-Process -FilePath $godot -ArgumentList $godotArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    # PowerShell 5.1 liefert den Exit-Code nur, wenn das Handle vorher abgefragt wurde.
    $null = $p.Handle
    $finished = $p.WaitForExit($timeoutSeconds * 1000)
    if (-not $finished) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        $p.WaitForExit()
    }
    $out = (Get-Content $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + "`n" + (Get-Content $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
    $code = $p.ExitCode
    $clean = ($out -split "`r?`n" | Where-Object { $_ -notmatch "^Godot Engine" -and $_.Trim() -ne "" }) -join "`n"
    if ($clean) { Write-Host $clean }
    $hasError = $out -match "SCRIPT ERROR|ERROR:|FEHLER"
    if (-not $finished) {
        Write-Host "   -> FEHLGESCHLAGEN (Zeitlimit von $timeoutSeconds s überschritten)" -ForegroundColor Red
        $failed += $name
    } elseif ($code -ne 0 -or $hasError) {
        Write-Host "   -> FEHLGESCHLAGEN (Code $code, Skriptfehler: $hasError)" -ForegroundColor Red
        $failed += $name
    } else {
        Write-Host "   -> bestanden" -ForegroundColor Green
    }
}

Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "Alle $($names.Count) Dateien bestanden (Skriptprüfung und Tests)." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Fehlgeschlagen: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
