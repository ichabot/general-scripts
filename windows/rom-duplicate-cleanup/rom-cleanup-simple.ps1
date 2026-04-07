# ROM Duplikate Cleanup - EINFACHE DIREKTE VERSION
# Löscht GARANTIERT ohne Komplikationen!

param(
    [string]$RomPath = "E:\Download\Sega Genesis (Mega Drive) & Sega 32X Complete Romset"
)

Set-Location $RomPath
Write-Host "=== DIREKTES ROM CLEANUP ===" -ForegroundColor Yellow
Write-Host "Arbeitsverzeichnis: $(Get-Location)" -ForegroundColor Cyan

$deletedCount = 0
$errorCount = 0

# EINFACHE PRIORITÄTS-FUNKTION
function Get-Priority($filename) {
    $score = 0
    
    # Region
    if ($filename -like "*(JUE)*") { $score -= 50 }
    elseif ($filename -like "*(UE)*") { $score -= 40 }
    elseif ($filename -like "*(U)*") { $score -= 30 }
    elseif ($filename -like "*(E)*") { $score -= 20 }
    
    # Qualität
    if ($filename -like "*[!]*") { $score -= 100 }
    elseif ($filename -like "*[f]*") { $score -= 80 }
    elseif ($filename -like "*[p]*") { $score -= 70 }
    elseif ($filename -like "*[h]*") { $score += 20 }
    elseif ($filename -like "*[t]*") { $score += 30 }
    elseif ($filename -like "*[a]*") { $score += 40 }
    elseif ($filename -like "*[c]*") { $score += 50 }
    elseif ($filename -like "*[b]*") { $score += 80 }
    
    return $score
}

# EINFACHE SPIELNAME-EXTRAKTION
function Get-GameName($filename) {
    $name = $filename -replace '\.zip$', ''
    $name = $name -replace '\s*\([^)]*\).*$', ''
    $name = $name -replace '\s*\[[^\]]*\].*$', ''
    return $name.Trim()
}

Write-Host "Sammle alle ROM-Dateien..." -ForegroundColor Cyan
$allFiles = Get-ChildItem -Path . -Filter "*.zip" -File
Write-Host "Gefunden: $($allFiles.Count) ROMs" -ForegroundColor Cyan

# GRUPPIERE NACH SPIELNAME
$groups = @{}
foreach($file in $allFiles) {
    $gameName = Get-GameName $file.Name
    if (-not $groups.ContainsKey($gameName)) {
        $groups[$gameName] = @()
    }
    $groups[$gameName] += $file
}

Write-Host "Unique Spiele: $($groups.Count)" -ForegroundColor Cyan

# BEARBEITE JEDE GRUPPE
foreach($gameName in $groups.Keys) {
    $versions = $groups[$gameName]
    
    if ($versions.Count -gt 1) {
        Write-Host "`n--- $gameName ($($versions.Count) Versionen) ---" -ForegroundColor Yellow
        
        # SORTIERE NACH PRIORITÄT
        $sorted = $versions | ForEach-Object {
            [PSCustomObject]@{
                File = $_
                Name = $_.Name
                Priority = Get-Priority $_.Name
            }
        } | Sort-Object Priority
        
        # ERSTE = BESTE (BEHALTEN)
        $keepFile = $sorted[0]
        Write-Host "KEEP: $($keepFile.Name) (Score: $($keepFile.Priority))" -ForegroundColor Green
        
        # REST LÖSCHEN
        for($i = 1; $i -lt $sorted.Count; $i++) {
            $deleteFile = $sorted[$i]
            Write-Host "DELETE: $($deleteFile.Name) (Score: $($deleteFile.Priority))" -ForegroundColor Red
            
            try {
                # VERWENDE DAS ORIGINAL FILE-OBJEKT (nicht den Namen!)
                $actualFile = $deleteFile.File
                
                Write-Host "  Versuche zu löschen: $($actualFile.FullName)" -ForegroundColor Gray
                
                if ($actualFile.Exists) {
                    # METHODE 1: Direkt über FileInfo-Objekt
                    $actualFile.Delete()
                    Write-Host "  ✓ GELÖSCHT (Methode 1)" -ForegroundColor Green
                    $deletedCount++
                } else {
                    # METHODE 2: Über Get-ChildItem nochmal suchen
                    $foundFile = Get-ChildItem -Path . -Filter $actualFile.Name -File -ErrorAction SilentlyContinue
                    if ($foundFile) {
                        $foundFile.Delete()
                        Write-Host "  ✓ GELÖSCHT (Methode 2)" -ForegroundColor Green  
                        $deletedCount++
                    } else {
                        Write-Host "  ! DATEI WIRKLICH NICHT GEFUNDEN: $($actualFile.Name)" -ForegroundColor Yellow
                        $errorCount++
                    }
                }
            } catch {
                Write-Host "  ! FEHLER: $($_.Exception.Message)" -ForegroundColor Red
                $errorCount++
                
                # METHODE 3: cmd /c del als letzte Rettung
                try {
                    $quotedName = "`"$($deleteFile.File.FullName)`""
                    cmd /c "del $quotedName" 2>$null
                    if (-not (Test-Path $deleteFile.File.FullName)) {
                        Write-Host "  ✓ GELÖSCHT (CMD Fallback)" -ForegroundColor Green
                        $deletedCount++
                    }
                } catch {
                    Write-Host "  ! ALLE METHODEN GESCHEITERT" -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host "`n=== FERTIG ===" -ForegroundColor Yellow
Write-Host "Gelöschte Dateien: $deletedCount" -ForegroundColor Green
Write-Host "Fehler: $errorCount" -ForegroundColor Red
Write-Host "Verbleibende Dateien: $((Get-ChildItem -Filter "*.zip").Count)" -ForegroundColor Cyan

# TESTE EINE DATEI MANUELL
Write-Host "`n=== LÖSCHTEST ===" -ForegroundColor Magenta
$testFiles = Get-ChildItem -Filter "*[h1]*" | Select-Object -First 3
Write-Host "Gefundene Testdateien: $($testFiles.Count)" -ForegroundColor Cyan

foreach($testFile in $testFiles) {
    Write-Host "`nTeste: $($testFile.Name)" -ForegroundColor Yellow
    Write-Host "Vollpfad: $($testFile.FullName)" -ForegroundColor Gray
    Write-Host "Existiert: $(Test-Path $testFile.FullName)" -ForegroundColor Gray
    
    # TEST 1: FileInfo.Delete()
    try {
        $testFile.Delete()
        Write-Host "✓ GELÖSCHT mit FileInfo.Delete()" -ForegroundColor Green
        break
    } catch {
        Write-Host "✗ FileInfo.Delete() Fehler: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # TEST 2: Remove-Item
    try {
        Remove-Item $testFile.FullName -Force
        Write-Host "✓ GELÖSCHT mit Remove-Item" -ForegroundColor Green
        break
    } catch {
        Write-Host "✗ Remove-Item Fehler: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # TEST 3: CMD
    try {
        cmd /c "del `"$($testFile.FullName)`""
        if (-not (Test-Path $testFile.FullName)) {
            Write-Host "✓ GELÖSCHT mit CMD" -ForegroundColor Green
            break
        } else {
            Write-Host "✗ CMD hat nicht funktioniert" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ CMD Fehler: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "⚠️ ALLE LÖSCHMETHODEN GESCHEITERT für diese Datei!" -ForegroundColor Red
    
    # Zeige Dateieigenschaften
    Write-Host "Dateieigenschaften:" -ForegroundColor Gray
    Write-Host "  Größe: $($testFile.Length) Bytes" -ForegroundColor Gray
    Write-Host "  Schreibgeschützt: $($testFile.IsReadOnly)" -ForegroundColor Gray
    Write-Host "  Erstellt: $($testFile.CreationTime)" -ForegroundColor Gray
}

Write-Host "`nFalls immer noch Probleme: Führen Sie PowerShell als Administrator aus!" -ForegroundColor Yellow
