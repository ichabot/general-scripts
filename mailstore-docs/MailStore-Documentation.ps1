# MailStore Installation Documentation Script mit API-Integration
# Erstellt eine umfassende Dokumentation der MailStore-Installation
# Autor: PowerShell Dokumentations-Script mit MailStore API
# Version: 2.1
  
param(
    [string]$OutputPath = "C:\Temp\MailStore_Documentation_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html",
    [string]$MailStoreServerPath = "C:\Program Files (x86)\MailStore\",
    [string]$MailStoreServer = "localhost",
    [int]$MailStorePort = 8463,
    [string]$MailStoreUsername = "admin",
    [string]$MailStorePassword = "",
    [string]$APIWrapperPath = "C:\Scripts\MailStore_Server_Scripting_Tutorial\PowerShell\API-Wrapper\MS.PS.Lib.psd1",
    [switch]$IncludePerformanceData,
    [switch]$UseAPIOnly
)
  
# HTML-Template für die Ausgabe
$htmlTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <title>MailStore Server Documentation - $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; }
        h2 { color: #34495e; border-bottom: 1px solid #bdc3c7; }
        h3 { color: #7f8c8d; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; }
        .info-box { background-color: #ecf0f1; padding: 10px; margin: 10px 0; border-left: 4px solid #3498db; }
        .warning { background-color: #fff3cd; border-left: 4px solid #ffc107; }
        .error { background-color: #f8d7da; border-left: 4px solid #dc3545; }
        pre { background-color: #f8f9fa; padding: 10px; border: 1px solid #e9ecef; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>MailStore Server Dokumentation</h1>
    <p><strong>Erstellt am:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')</p>
    <p><strong>Server:</strong> $env:COMPUTERNAME</p>
    
    ##CONTENT##
    
    <hr>
    <p><em>Generiert mit PowerShell MailStore Dokumentations-Script</em></p>
</body>
</html>
"@
  
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(if($Level -eq "ERROR"){"Red"} elseif($Level -eq "WARN"){"Yellow"} else{"Green"})
}
  
# MailStore API Client initialisieren
$Global:MSApiClient = $null
$Global:UseMailStoreAPI = $false
  
function Initialize-MailStoreAPI {
    Write-Log "Versuche MailStore API zu initialisieren..."
    
    # Suche nach API Wrapper
    $possiblePaths = @(
        $APIWrapperPath,
        "$MailStoreServerPath\PowerShell\API-Wrapper\MS.PS.Lib.psd1",
        "$env:ProgramFiles\MailStore Server\PowerShell\API-Wrapper\MS.PS.Lib.psd1",
        "$env:ProgramFiles(x86)\MailStore Server\PowerShell\API-Wrapper\MS.PS.Lib.psd1",
        ".\API-Wrapper\MS.PS.Lib.psd1",
        "..\API-Wrapper\MS.PS.Lib.psd1"
    )
    
    $apiWrapperFound = $false
    foreach ($path in $possiblePaths) {
        if ($path -and (Test-Path $path)) {
            try {
                # Automatisches Entsperren der API Wrapper Dateien
                $wrapperDirectory = Split-Path $path -Parent
                Write-Log "Entsperre API Wrapper Dateien in: $wrapperDirectory"
                
                try {
                    Get-ChildItem $wrapperDirectory -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
                    Write-Log "API Wrapper Dateien erfolgreich entsperrt"
                } catch {
                    Write-Log "Warnung: Konnte API Wrapper Dateien nicht entsperren: $($_.Exception.Message)" "WARN"
                }
                
                # Versuche Execution Policy temporär zu setzen
                $currentPolicy = Get-ExecutionPolicy -Scope Process -ErrorAction SilentlyContinue
                if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "AllSigned") {
                    try {
                        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
                        Write-Log "Execution Policy temporär auf Bypass gesetzt für diese Session"
                    } catch {
                        Write-Log "Warnung: Konnte Execution Policy nicht setzen: $($_.Exception.Message)" "WARN"
                    }
                }
                
                Import-Module $path -Force
                Write-Log "API Wrapper erfolgreich geladen von: $path"
                $apiWrapperFound = $true
                break
            } catch {
                Write-Log "Fehler beim Laden des API Wrappers von $path : $($_.Exception.Message)" "WARN"
                
                # Zusätzliche Hilfe bei Execution Policy Problemen
                if ($_.Exception.Message -like "*digital*signiert*" -or $_.Exception.Message -like "*Execution*Policy*") {
                    Write-Log "      Tipp: Führen Sie PowerShell als Administrator aus und verwenden Sie:" "INFO"
                    Write-Log "   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" "INFO"
                    Write-Log "   Oder entsperren Sie die Dateien manuell mit:" "INFO"
                    Write-Log "   Get-ChildItem '$wrapperDirectory' -Recurse | Unblock-File" "INFO"
                }
            }
        }
    }
    
    if (-not $apiWrapperFound) {
        Write-Log "MailStore PowerShell API Wrapper nicht gefunden. Systembasierte Dokumentation wird verwendet." "WARN"
        return $false
    }
    
    # Passwort abfragen falls nicht angegeben
    if (-not $MailStorePassword) {
        $securePassword = Read-Host "MailStore Admin Passwort eingeben" -AsSecureString
        $MailStorePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    }
    
    # API Client erstellen
    try {
        $Global:MSApiClient = New-MSApiClient -Username $MailStoreUsername -Password $MailStorePassword -MailStoreServer $MailStoreServer -Port $MailStorePort -IgnoreInvalidSSLCerts
        
        # Verbindung testen
        $testResult = Invoke-MSApiCall $Global:MSApiClient "GetServerInfo"
        if ($testResult.statusCode -eq "succeeded") {
            $serverInfo = $testResult.result
            Write-Log "MailStore API erfolgreich verbunden - Server: $($serverInfo.machineName), Version: $($serverInfo.version)"
            $Global:UseMailStoreAPI = $true
            return $true
        } else {
            Write-Log "MailStore API Verbindung fehlgeschlagen: $($testResult.error)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Fehler bei MailStore API Initialisierung: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
  
function Invoke-MailStoreAPI {
    param(
        [string]$Command,
        [hashtable]$Parameters = @{}
    )
    
    if (-not $Global:UseMailStoreAPI) {
        return $null
    }
    
    try {
        $result = Invoke-MSApiCall $Global:MSApiClient $Command $Parameters
        if ($result.statusCode -eq "succeeded") {
            return $result.result
        } else {
            Write-Log "MailStore API Fehler für $Command : $($result.error)" "WARN"
            return $null
        }
    } catch {
        Write-Log "Fehler beim MailStore API Aufruf $Command : $($_.Exception.Message)" "WARN"
        return $null
    }
}
  
function Get-SystemInfo {
    Write-Log "Sammle Systeminformationen..."
    
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $processor = Get-CimInstance -ClassName Win32_Processor
    $memory = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    
    $systemInfo = @"
    <h2>  ️ Systeminformationen</h2>
    <table>
        <tr><th>Parameter</th><th>Wert</th></tr>
        <tr><td>Servername</td><td>$($computer.Name)</td></tr>
        <tr><td>Betriebssystem</td><td>$($os.Caption) $($os.Version)</td></tr>
        <tr><td>Architektur</td><td>$($os.OSArchitecture)</td></tr>
        <tr><td>Prozessor</td><td>$($processor[0].Name)</td></tr>
        <tr><td>Prozessorkerne</td><td>$($processor[0].NumberOfCores)</td></tr>
        <tr><td>RAM gesamt</td><td>$([math]::Round($memory.Sum / 1GB, 2)) GB</td></tr>
        <tr><td>Domäne/Arbeitsgruppe</td><td>$($computer.Domain)</td></tr>
        <tr><td>Letzter Neustart</td><td>$($os.LastBootUpTime)</td></tr>
    </table>
"@
    return $systemInfo
}
  
function Get-MailStoreServices {
    Write-Log "Prüfe MailStore Services..."
    
    $services = Get-Service | Where-Object { $_.Name -like "*MailStore*" -or $_.DisplayName -like "*MailStore*" }
    
    if ($services) {
        $serviceTable = "<h2>   MailStore Services</h2><table><tr><th>Service Name</th><th>Display Name</th><th>Status</th><th>Start Type</th><th>Account</th></tr>"
        
        foreach ($service in $services) {
            $serviceDetails = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name)'"
            $status = if($service.Status -eq "Running") { "   Running" } else { "   $($service.Status)" }
            $serviceTable += "<tr><td>$($service.Name)</td><td>$($service.DisplayName)</td><td>$status</td><td>$($serviceDetails.StartMode)</td><td>$($serviceDetails.StartName)</td></tr>"
        }
        $serviceTable += "</table>"
    } else {
        $serviceTable = "<h2>   MailStore Services</h2><div class='warning info-box'>⚠️ Keine MailStore Services gefunden</div>"
    }
    
    return $serviceTable
}
  
function Get-MailStoreInstallation {
    Write-Log "Analysiere MailStore Installation..."
    
    $installInfo = "<h2>   MailStore Installation</h2>"
    
    # MailStore Server Pfad prüfen
    if (Test-Path $MailStoreServerPath) {
        $installInfo += "<div class='info-box'>✅ MailStore Server Installationspfad gefunden: $MailStoreServerPath</div>"
        
        # Version ermitteln
        $exePath = Join-Path $MailStoreServerPath "MailStoreServer.exe"
        if (Test-Path $exePath) {
            $version = (Get-ItemProperty $exePath).VersionInfo.ProductVersion
            $installInfo += "<p><strong>Version:</strong> $version</p>"
        }
        
        # Installationsverzeichnis analysieren
        $directories = Get-ChildItem $MailStoreServerPath -Directory
        $installInfo += "<h3>Installationsverzeichnisse:</h3><ul>"
        foreach ($dir in $directories) {
            $size = (Get-ChildItem $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $sizeGB = [math]::Round($size / 1GB, 2)
            $installInfo += "<li>$($dir.Name) ($sizeGB GB)</li>"
        }
        $installInfo += "</ul>"
        
    } else {
        $installInfo += "<div class='error info-box'>❌ MailStore Server nicht im Standardpfad gefunden: $MailStoreServerPath</div>"
        
        # Alternative Suchpfade
        $searchPaths = @(
            "${env:ProgramFiles}\MailStore*",
            "${env:ProgramFiles(x86)}\MailStore*",
            "${env:ProgramFiles}\deepinvent\MailStore*"
        )
        
        foreach ($path in $searchPaths) {
            $found = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            if ($found) {
                $installInfo += "<div class='info-box'>   Alternative Installation gefunden: $($found.FullName)</div>"
                break
            }
        }
    }
    
    return $installInfo
}
  
function Get-MailStoreConfiguration {
    Write-Log "Lade MailStore Konfiguration..."
    
    $configInfo = "<h2>⚙️ MailStore Konfiguration</h2>"
    
    if ($Global:UseMailStoreAPI) {
        # Server-Informationen via API
        $serverInfo = Invoke-MailStoreAPI "GetServerInfo"
        if ($serverInfo) {
            $configInfo += "<div class='info-box'>✅ <strong>MailStore API verbunden</strong></div>"
            $configInfo += "<h3>Server-Informationen:</h3><table><tr><th>Parameter</th><th>Wert</th></tr>"
            $configInfo += "<tr><td>Version</td><td>$($serverInfo.version)</td></tr>"
            $configInfo += "<tr><td>Machine Name</td><td>$($serverInfo.machineName)</td></tr>"
            $configInfo += "</table>"
        }
        
        # Service-Konfiguration
        $serviceConfig = Invoke-MailStoreAPI "GetServiceConfiguration"
        if ($serviceConfig) {
            $configInfo += "<h3>Service-Konfiguration:</h3><table><tr><th>Parameter</th><th>Wert</th></tr>"
            $configInfo += "<tr><td>Basis-Verzeichnis</td><td>$($serviceConfig.baseDirectory)</td></tr>"
            $configInfo += "<tr><td>Debug-Log</td><td>$(if($serviceConfig.debugLog){'Aktiviert'}else{'Deaktiviert'})</td></tr>"
            $configInfo += "<tr><td>Audit-Log Speicherort</td><td>$($serviceConfig.auditLogLocation)</td></tr>"
            if ($serviceConfig.serverCertificate) {
                # Zertifikat-Thumbprint korrekt extrahieren
                $certThumbprint = if ($serviceConfig.serverCertificate.thumbprint) {
                    $serviceConfig.serverCertificate.thumbprint
                } elseif ($serviceConfig.serverCertificate -is [string]) {
                    $serviceConfig.serverCertificate
                } else {
                    "Konfiguriert"
                }
                $configInfo += "<tr><td>Server-Zertifikat (Thumbprint)</td><td>$certThumbprint</td></tr>"
            }
            $configInfo += "</table>"
        }
        
        # Erweiterte Lizenz-Informationen
        $licenseInfo = Invoke-MailStoreAPI "GetLicenseInformation"
        if ($licenseInfo) {
            $configInfo += "<h3>Lizenz-Informationen:</h3><table><tr><th>Parameter</th><th>Wert</th></tr>"
            $configInfo += "<tr><td>Lizenziert für</td><td>$($licenseInfo.licensedTo)</td></tr>"
            $configInfo += "<tr><td>Produkt Version</td><td>$($licenseInfo.productVersion)</td></tr>"
            $configInfo += "<tr><td>Max. Named Users</td><td>$($licenseInfo.maxNamedUsers)</td></tr>"
            $configInfo += "<tr><td>Aktuelle Named Users</td><td>$($licenseInfo.namedUsers)</td></tr>"
            $configInfo += "<tr><td>Verfügbare User-Lizenzen</td><td>$($licenseInfo.maxNamedUsers - $licenseInfo.namedUsers)</td></tr>"
            
            # Lizenz-Laufzeit
            if ($licenseInfo.validFrom) {
                $validFrom = [DateTime]::Parse($licenseInfo.validFrom)
                $configInfo += "<tr><td>Gültig ab</td><td>$($validFrom.ToString('dd.MM.yyyy'))</td></tr>"
            }
            
            if ($licenseInfo.validTo -or $licenseInfo.expirationDate) {
                $expirationDate = if ($licenseInfo.validTo) { $licenseInfo.validTo } else { $licenseInfo.expirationDate }
                $expDate = [DateTime]::Parse($expirationDate)
                $daysRemaining = ($expDate - (Get-Date)).Days
                
                $expirationStatus = if ($daysRemaining -lt 0) {
                    "   Abgelaufen vor $([Math]::Abs($daysRemaining)) Tagen"
                } elseif ($daysRemaining -lt 30) {
                    "   Läuft in $daysRemaining Tagen ab"
                } elseif ($daysRemaining -lt 90) {
                    "   Läuft in $daysRemaining Tagen ab"
                } else {
                    "   Noch $daysRemaining Tage gültig"
                }
                
                $configInfo += "<tr><td>Gültig bis</td><td>$($expDate.ToString('dd.MM.yyyy')) - $expirationStatus</td></tr>"
            }
            
            # Support-Laufzeit
            if ($licenseInfo.supportExpirationDate) {
                $supportExpDate = [DateTime]::Parse($licenseInfo.supportExpirationDate)
                $supportDaysRemaining = ($supportExpDate - (Get-Date)).Days
                
                $supportStatus = if ($supportDaysRemaining -lt 0) {
                    "   Abgelaufen vor $([Math]::Abs($supportDaysRemaining)) Tagen"
                } elseif ($supportDaysRemaining -lt 30) {
                    "   Läuft in $supportDaysRemaining Tagen ab"
                } elseif ($supportDaysRemaining -lt 90) {
                    "   Läuft in $supportDaysRemaining Tagen ab"  
                } else {
                    "   Noch $supportDaysRemaining Tage gültig"
                }
                
                $configInfo += "<tr><td>Support gültig bis</td><td>$($supportExpDate.ToString('dd.MM.yyyy')) - $supportStatus</td></tr>"
            }
            
            # Lizenz-Typ
            if ($licenseInfo.licenseType) {
                $configInfo += "<tr><td>Lizenz-Typ</td><td>$($licenseInfo.licenseType)</td></tr>"
            }
            
            $configInfo += "</table>"
            
            # Lizenz-Warnungen
            if ($licenseInfo.namedUsers -ge ($licenseInfo.maxNamedUsers * 0.9)) {
                $configInfo += "<div class='warning info-box'>⚠️ <strong>Warnung:</strong> Über 90% der User-Lizenzen sind belegt!</div>"
            }
            
            if ($licenseInfo.supportExpirationDate) {
                $supportDays = ($supportExpDate - (Get-Date)).Days
                if ($supportDays -lt 90 -and $supportDays -gt 0) {
                    $configInfo += "<div class='warning info-box'>⚠️ <strong>Support-Warnung:</strong> Der Support läuft in $supportDays Tagen ab!</div>"
                } elseif ($supportDays -le 0) {
                    $configInfo += "<div class='error info-box'>❌ <strong>Support abgelaufen:</strong> Der Support ist vor $([Math]::Abs($supportDays)) Tagen abgelaufen!</div>"
                }
            }
        }
    }
    
    if (-not $Global:UseMailStoreAPI) {
        # Fallback: Registry-Suche
        $registryPaths = @(
            "HKLM:\SOFTWARE\MailStore Software\MailStore Server",
            "HKLM:\SOFTWARE\WOW6432Node\MailStore Software\MailStore Server"
        )
        
        foreach ($regPath in $registryPaths) {
            if (Test-Path $regPath) {
                $configInfo += "<h3>Registry Konfiguration:</h3><table><tr><th>Parameter</th><th>Wert</th></tr>"
                $regItems = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                if ($regItems) {
                    $regItems.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                        $configInfo += "<tr><td>$($_.Name)</td><td>$($_.Value)</td></tr>"
                    }
                }
                $configInfo += "</table>"
                break
            }
        }
    }
    
    return $configInfo
}
  
function Get-MailStoreArchives {
    Write-Log "Analysiere MailStore Archive Stores..."
    
    $archiveInfo = "<h2>  ️ MailStore Archive Stores</h2>"
    
    if ($Global:UseMailStoreAPI) {
        # Archive Stores über API abrufen (ohne Größenberechnung)
        $stores = Invoke-MailStoreAPI "GetStores" @{includeSize = $false}
        
        if ($stores) {
            $archiveInfo += "<table><tr><th>Name</th><th>Typ</th><th>Status</th><th>Datenbank-Pfad</th><th>Content-Pfad</th></tr>"
            
            foreach ($store in $stores) {
                $statusIcon = switch ($store.requestedState) {
                    "current" { "   Current" }
                    "normal" { "   Normal" }  
                    "writeProtected" { "   Write Protected" }
                    "disabled" { "   Disabled" }
                    default { "❓ $($store.requestedState)" }
                }
                
                $dbPath = if ($store.databasePath) { $store.databasePath } else { "Standard" }
                $contentPath = if ($store.contentPath) { $store.contentPath } else { "Standard" }
                
                $archiveInfo += "<tr><td>$($store.name)</td><td>$($store.type)</td><td>$statusIcon</td><td>$dbPath</td><td>$contentPath</td></tr>"
            }
            $archiveInfo += "</table>"
            
            # Archive Store Statistiken
            $totalStores = $stores.Count
            $currentStores = ($stores | Where-Object { $_.requestedState -eq "current" }).Count
            $normalStores = ($stores | Where-Object { $_.requestedState -eq "normal" }).Count
            $protectedStores = ($stores | Where-Object { $_.requestedState -eq "writeProtected" }).Count
            $disabledStores = ($stores | Where-Object { $_.requestedState -eq "disabled" }).Count
            
            $archiveInfo += "<div class='info-box'>"
            $archiveInfo += "<strong>Archive Store Übersicht:</strong><br>"
            $archiveInfo += "• Gesamte Archive Stores: $totalStores<br>"
            $archiveInfo += "• Aktuelle Archive Stores: $currentStores<br>"
            $archiveInfo += "• Normale Archive Stores: $normalStores<br>"
            $archiveInfo += "• Schreibgeschützte Archive Stores: $protectedStores<br>"
            $archiveInfo += "• Deaktivierte Archive Stores: $disabledStores<br>"
            $archiveInfo += "</div>"
            
        } else {
            $archiveInfo += "<div class='warning info-box'>⚠️ Keine Archive Stores gefunden oder API-Zugriff fehlgeschlagen</div>"
        }
        
    } else {
        $archiveInfo += "<div class='error info-box'>❌ MailStore API nicht verfügbar - Archive Store Informationen können nur über die API abgerufen werden</div>"
        $archiveInfo += "<div class='info-box'>   <strong>Info:</strong> MailStore verwendet keine traditionellen SQL-Datenbanken. Alle E-Mails werden in speziellen Archive Store Dateien (Flatfiles) gespeichert.</div>"
    }
    
    return $archiveInfo
}
  
function Get-MailStoreFolderStructure {
    Write-Log "Analysiere MailStore Ordner-Struktur..."
    
    $folderInfo = "<h2>   MailStore Ordner-Struktur</h2>"
    
    if ($Global:UseMailStoreAPI) {
        # Versuche verschiedene Methoden, Ordner abzurufen
        $folders = $null
        
        # Methode 1: Mit maxLevels Parameter
        if (-not $folders) {
            $folders = Invoke-MailStoreAPI "GetChildFolders" @{maxLevels = 2}
        }
        
        # Methode 2: Ohne Parameter
        if (-not $folders) {
            $folders = Invoke-MailStoreAPI "GetChildFolders"
        }
        
        # Methode 3: Mit leerem folder Parameter
        if (-not $folders) {
            $folders = Invoke-MailStoreAPI "GetChildFolders" @{folder = ""}
        }
        
        if ($folders -and $folders.Count -gt 0) {
            $folderInfo += "<table><tr><th>Ordner-Name</th><th>Typ</th><th>Pfad</th></tr>"
            
            $folderCount = 0
            
            foreach ($folder in $folders) {
                try {
                    # Ordner-Name extrahieren (kann in verschiedenen Eigenschaften sein)
                    $folderName = "Unbekannt"
                    if ($folder.folder) { 
                        $folderName = $folder.folder 
                    } elseif ($folder.name) { 
                        $folderName = $folder.name 
                    } elseif ($folder.path) { 
                        $folderName = $folder.path 
                    }
                    
                    # Ordner-Typ bestimmen
                    $folderType = "   Benutzer"
                    
                    if ($folderName -eq "@catchall") { $folderType = "   Catch-All" }
                    elseif ($folderName -like "pf-*") { $folderType = "   Öffentlicher Ordner" }
                    elseif ($folderName -like "*admin*") { $folderType = "⚙️ Administrator" }
                    elseif ($folderName -like "*journal*") { $folderType = "   Journal" }
                    elseif ($folderName -like "*auditor*") { $folderType = "   Auditor" }
                    elseif ($folderName -like "*public*") { $folderType = "   Öffentlich" }
                    
                    $folderPath = if ($folder.path) { $folder.path } else { $folderName }
                    
                    $folderInfo += "<tr><td>$folderName</td><td>$folderType</td><td>$folderPath</td></tr>"
                    $folderCount++
                    
                } catch {
                    Write-Log "Fehler beim Verarbeiten von Ordner: $($_.Exception.Message)" "WARN"
                }
            }
            $folderInfo += "</table>"
            
            $folderInfo += "<div class='info-box'>"
            $folderInfo += "<strong>Ordner-Übersicht:</strong><br>"
            $folderInfo += "• Gesamte Ordner: $folderCount<br>"
            $folderInfo += "</div>"
            
            # Hinweis zu Ordner-Statistiken
            $folderInfo += "<div class='info-box'>   <strong>Hinweis:</strong> Detaillierte Ordner-Statistiken (Nachrichten-Anzahl, Größe) erfordern zusätzliche API-Berechtigungen oder müssen einzeln pro Ordner abgerufen werden.</div>"
            
        } else {
            # Fallback: Benutzer-basierte Ordner anzeigen
            $users = Invoke-MailStoreAPI "GetUsers"
            if ($users) {
                $folderInfo += "<h3>Benutzer-basierte Ordner-Struktur:</h3>"
                $folderInfo += "<table><tr><th>Benutzer</th><th>Vollname</th><th>E-Mail-Ordner</th></tr>"
                
                foreach ($user in $users) {
                    $userDetails = Invoke-MailStoreAPI "GetUserInfo" @{userName = $user.userName}
                    if ($userDetails) {
                        $emailAddresses = if ($userDetails.emailAddresses) { ($userDetails.emailAddresses -join ", ") } else { "Keine" }
                        $folderInfo += "<tr><td>$($user.userName)</td><td>$($userDetails.fullName)</td><td>$emailAddresses</td></tr>"
                    }
                }
                $folderInfo += "</table>"
                
                $folderInfo += "<div class='info-box'>"
                $folderInfo += "<strong>Benutzer-Statistiken:</strong><br>"
                $folderInfo += "• Gesamte Benutzer mit möglichen E-Mail-Ordnern: $($users.Count)<br>"
                $folderInfo += "• Hinweis: Jeder Benutzer kann einen eigenen E-Mail-Ordner haben<br>"
                $folderInfo += "</div>"
            } else {
                $folderInfo += "<div class='warning info-box'>⚠️ Keine Ordner-Informationen verfügbar. Möglicherweise fehlen API-Berechtigungen.</div>"
            }
        }
        
    } else {
        $folderInfo += "<div class='error info-box'>❌ MailStore API nicht verfügbar - Ordner-Informationen können nur über die API abgerufen werden</div>"
    }
    
    return $folderInfo
}
  
function Get-MailStoreUsersAndProfiles {
    Write-Log "Analysiere MailStore Benutzer und Profile..."
    
    $info = "<h2>   MailStore Benutzer und Profile</h2>"
    
    if ($Global:UseMailStoreAPI) {
        # Benutzer abrufen
        $users = Invoke-MailStoreAPI "GetUsers"
        if ($users) {
            $info += "<h3>Benutzer:</h3><table><tr><th>Benutzername</th><th>Vollname</th><th>Authentifizierung</th><th>Rechte</th><th>Login-Methoden</th></tr>"
            
            foreach ($user in $users) {
                $userDetails = Invoke-MailStoreAPI "GetUserInfo" @{userName = $user.userName}
                if ($userDetails) {
                    $authMethod = if ($userDetails.authentication -eq "directoryServices") { "Directory Services" } else { "Integriert" }
                    $privileges = if ($userDetails.privileges) { ($userDetails.privileges -join ", ") } else { "Keine" }
                    $loginPrivileges = if ($userDetails.loginPrivileges) { ($userDetails.loginPrivileges -join ", ") } else { "Keine" }
                    
                    $info += "<tr><td>$($user.userName)</td><td>$($userDetails.fullName)</td><td>$authMethod</td><td>$privileges</td><td>$loginPrivileges</td></tr>"
                }
            }
            $info += "</table>"
            
            # Benutzer-Statistiken
            $totalUsers = $users.Count
            $adminUsers = 0
            $dsUsers = 0
            
            foreach ($user in $users) {
                $userDetails = Invoke-MailStoreAPI "GetUserInfo" @{userName = $user.userName}
                if ($userDetails) {
                    if ($userDetails.privileges -contains "admin") { $adminUsers++ }
                    if ($userDetails.authentication -eq "directoryServices") { $dsUsers++ }
                }
            }
            
            $info += "<div class='info-box'>"
            $info += "<strong>Benutzer-Statistiken:</strong><br>"
            $info += "• Gesamte Benutzer: $totalUsers<br>"
            $info += "• Administratoren: $adminUsers<br>"
            $info += "• Directory Services Benutzer: $dsUsers<br>"
            $info += "• Lokale Benutzer: $($totalUsers - $dsUsers)<br>"
            $info += "</div>"
        }
        
        # Profile abrufen
        $profiles = Invoke-MailStoreAPI "GetProfiles" @{raw = $true}
        if ($profiles) {
            $info += "<h3>Archivierungs- und Export-Profile:</h3>"
            
            $info += "<table><tr><th>ID</th><th>Name</th><th>Typ</th><th>Server</th><th>Benutzer</th><th>Automatisch</th><th>Pause</th></tr>"
            
            foreach ($profile in $profiles) {
                # Profil-Name (ist direkt im 'name' Feld)
                $profileName = if ($profile.name) { $profile.name } else { "Unbekannt" }
                
                # Profil-Typ basierend auf Connector bestimmen
                $profileType = "Unbekannt"
                if ($profile.connector) {
                    switch ($profile.connector) {
                        "Exchange" { $profileType = "Microsoft Exchange" }
                        "IMAP" { $profileType = "IMAP Server" }
                        "POP3" { $profileType = "POP3 Server" }
                        "Office365" { $profileType = "Microsoft 365" }
                        "Gmail" { $profileType = "Google Gmail" }
                        "FileSystem" { $profileType = "Dateisystem" }
                        "Outlook" { $profileType = "Microsoft Outlook" }
                        "EWS" { $profileType = "Exchange Web Services" }
                        default { $profileType = $profile.connector }
                    }
                }
                
                # Server-Information aus details-Objekt
                $serverInfo = "Nicht konfiguriert"
                if ($profile.details) {
                    if ($profile.details.host) { 
                        $serverInfo = $profile.details.host 
                    } elseif ($profile.details.server) { 
                        $serverInfo = $profile.details.server 
                    } elseif ($profile.details.hostname) { 
                        $serverInfo = $profile.details.hostname 
                    }
                }
                
                # Benutzer-Information
                $userInfo = "Nicht konfiguriert"
                if ($profile.details -and $profile.details.userName) {
                    $userInfo = $profile.details.userName
                }
                
                # Automatische Ausführung prüfen
                $isAutomatic = "   Nein"
                if ($profile.serverSideExecution -and $profile.serverSideExecution.automatic) {
                    $isAutomatic = "   Ja"
                }
                
                # Pause zwischen Ausführungen
                $pauseInfo = "Standard"
                if ($profile.serverSideExecution -and $profile.serverSideExecution.automaticPauseBetweenExecutions) {
                    $pauseSeconds = $profile.serverSideExecution.automaticPauseBetweenExecutions
                    if ($pauseSeconds -ge 3600) {
                        $pauseHours = [math]::Round($pauseSeconds / 3600, 1)
                        $pauseInfo = "$pauseHours Stunden"
                    } elseif ($pauseSeconds -ge 60) {
                        $pauseMinutes = [math]::Round($pauseSeconds / 60, 0)
                        $pauseInfo = "$pauseMinutes Minuten"
                    } else {
                        $pauseInfo = "$pauseSeconds Sekunden"
                    }
                }
                
                $profileId = if ($profile.id) { $profile.id } else { "N/A" }
                
                $info += "<tr><td>$profileId</td><td>$profileName</td><td>$profileType</td><td>$serverInfo</td><td>$userInfo</td><td>$isAutomatic</td><td>$pauseInfo</td></tr>"
            }
            $info += "</table>"
            
            # Erweiterte Profil-Statistiken
            $totalProfiles = $profiles.Count
            $automaticProfiles = ($profiles | Where-Object { $_.serverSideExecution -and $_.serverSideExecution.automatic }).Count
            $exchangeProfiles = ($profiles | Where-Object { $_.connector -eq "Exchange" }).Count
            $connectorTypes = $profiles | Group-Object -Property connector
            
            $info += "<div class='info-box'>"
            $info += "<strong>Profil-Statistiken:</strong><br>"
            $info += "• Gesamte Profile: $totalProfiles<br>"
            $info += "• Automatische Profile: $automaticProfiles<br>"
            $info += "• Exchange Profile: $exchangeProfiles<br>"
            $info += "<strong>Profile nach Typ:</strong><br>"
            foreach ($connectorType in $connectorTypes) {
                $typeName = switch ($connectorType.Name) {
                    "Exchange" { "Microsoft Exchange" }
                    "IMAP" { "IMAP Server" }
                    "POP3" { "POP3 Server" }
                    "Office365" { "Microsoft 365" }
                    default { $connectorType.Name }
                }
                $info += "• $typeName : $($connectorType.Count)<br>"
            }
            $info += "</div>"
            
            # Lösch-Einstellungen dokumentieren
            $profilesWithDeletion = $profiles | Where-Object { $_.details -and $_.details.deleteInMailbox }
            if ($profilesWithDeletion) {
                $info += "<h4>   E-Mail Lösch-Einstellungen:</h4>"
                $info += "<table><tr><th>Profil</th><th>Lösch-Regel</th><th>Beschreibung</th></tr>"
                
                foreach ($profile in $profilesWithDeletion) {
                    $deleteRule = $profile.details.deleteInMailbox
                    $description = switch -Wildcard ($deleteRule) {
                        "*never*" { "E-Mails werden niemals gelöscht" }
                        "*immediately*" { "E-Mails werden sofort nach Archivierung gelöscht" }
                        "*if-older-than-*" { 
                            $timePattern = $deleteRule -replace "if-older-than-", ""
                            "E-Mails werden gelöscht wenn älter als $timePattern"
                        }
                        default { $deleteRule }
                    }
                    
                    $info += "<tr><td>$($profile.name)</td><td>$deleteRule</td><td>$description</td></tr>"
                }
                $info += "</table>"
                
                $info += "<div class='warning info-box'>"
                $info += "⚠️ <strong>Wichtig:</strong> $($profilesWithDeletion.Count) Profile haben automatische Lösch-Regeln konfiguriert!"
                $info += "</div>"
            }
        }
        
        # Jobs abrufen
        $jobs = Invoke-MailStoreAPI "GetJobs"
        if ($jobs) {
            $info += "<h3>Geplante Jobs:</h3><table><tr><th>Name</th><th>Typ</th><th>Zeitplan</th><th>Status</th><th>Besitzer</th><th>Beschreibung</th></tr>"
            
            foreach ($job in $jobs) {
                # Job-Typ besser bestimmen
                $jobType = "Unbekannt"
                $jobDescription = ""
                
                if ($job.action) {
                    switch -Wildcard ($job.action) {
                        "*Backup*" { 
                            $jobType = "Backup"
                            $jobDescription = "Erstellt Sicherungskopien der Archive"
                        }
                        "*Retention*" { 
                            $jobType = "Retention/Löschung"
                            $jobDescription = "Löscht E-Mails nach definierten Regeln"
                        }
                        "*Archive*" { 
                            $jobType = "Archivierung"
                            $jobDescription = "Automatische E-Mail Archivierung"
                        }
                        "*Export*" { 
                            $jobType = "Export"
                            $jobDescription = "Exportiert E-Mails"
                        }
                        "*Compact*" { 
                            $jobType = "Wartung"
                            $jobDescription = "Komprimiert Archive Store"
                        }
                        "*Verify*" { 
                            $jobType = "Verifikation"
                            $jobDescription = "Überprüft Archive Integrität"
                        }
                        "*Index*" { 
                            $jobType = "Indizierung"
                            $jobDescription = "Aktualisiert Suchindexe"
                        }
                        "*Report*" { 
                            $jobType = "Bericht"
                            $jobDescription = "Generiert Statusberichte"
                        }
                        default { 
                            $jobType = "Sonstiges"
                            $jobDescription = $job.action
                        }
                    }
                }
                
                $schedule = "Unbekannt"
                if ($job.schedule) {
                    if ($job.schedule.time) {
                        $schedule = "Täglich um $($job.schedule.time)"
                    } elseif ($job.schedule.interval) {
                        $schedule = "Alle $($job.schedule.interval) Minuten"
                    } elseif ($job.schedule.dayOfWeek -and $job.schedule.time) {
                        $schedule = "$($job.schedule.dayOfWeek) um $($job.schedule.time)"
                    }
                }
                
                $status = if ($job.enabled) { "   Aktiviert" } else { "   Deaktiviert" }
                
                $info += "<tr><td>$($job.name)</td><td>$jobType</td><td>$schedule</td><td>$status</td><td>$($job.owner)</td><td>$jobDescription</td></tr>"
            }
            $info += "</table>"
        }
        
        # Retention Policies (automatisches Löschen) abrufen
        $retentionPolicies = Invoke-MailStoreAPI "GetRetentionPolicies"
        if ($retentionPolicies) {
            $info += "<h3>   Retention Policies (Automatisches Löschen):</h3>"
            $info += "<table><tr><th>Name</th><th>Zeitraum</th><th>Referenzdatum</th><th>Aktion</th><th>Suchkriterien</th><th>Status</th></tr>"
            
            foreach ($policy in $retentionPolicies) {
                $period = "$($policy.period) $($policy.periodInterval)"
                if ($policy.periodInterval -eq "year") { $period += if ($policy.period -eq 1) { " Jahr" } else { " Jahre" } }
                elseif ($policy.periodInterval -eq "month") { $period += if ($policy.period -eq 1) { " Monat" } else { " Monate" } }
                elseif ($policy.periodInterval -eq "day") { $period += if ($policy.period -eq 1) { " Tag" } else { " Tage" } }
                
                $referenceDate = if ($policy.referenceDateType -eq "ArchiveDate") { "Archivierungsdatum" } else { "Nachrichtendatum" }
                $action = if ($policy.delete) { "  ️ Löschen" } else { "⚠️ Kennzeichnen" }
                $status = if ($policy.enabled) { "   Aktiv" } else { "   Inaktiv" }
                
                # Suchkriterien zusammenfassen
                $criteria = @()
                if ($policy.searchCriteria.from) { $criteria += "Von: $($policy.searchCriteria.from)" }
                if ($policy.searchCriteria.to) { $criteria += "An: $($policy.searchCriteria.to)" }
                if ($policy.searchCriteria.query) { $criteria += "Suche: $($policy.searchCriteria.query)" }
                if ($policy.searchCriteria.excludedArchives) { $criteria += "Ausgeschlossen: $($policy.searchCriteria.excludedArchives -join ', ')" }
                
                $criteriaText = if ($criteria.Count -gt 0) { $criteria -join "<br>" } else { "Alle E-Mails" }
                
                $info += "<tr><td>$($policy.name)</td><td>$period</td><td>$referenceDate</td><td>$action</td><td>$criteriaText</td><td>$status</td></tr>"
            }
            $info += "</table>"
            
            # Retention Policy Statistiken
            $activePolicies = ($retentionPolicies | Where-Object { $_.enabled }).Count
            $deletePolicies = ($retentionPolicies | Where-Object { $_.delete }).Count
            
            $info += "<div class='info-box'>"
            $info += "<strong>Retention Policy Übersicht:</strong><br>"
            $info += "• Gesamte Policies: $($retentionPolicies.Count)<br>"
            $info += "• Aktive Policies: $activePolicies<br>"
            $info += "• Lösch-Policies: $deletePolicies<br>"
            $info += "• Kennzeichnungs-Policies: $($retentionPolicies.Count - $deletePolicies)<br>"
            $info += "</div>"
            
            if ($deletePolicies -gt 0) {
                $info += "<div class='warning info-box'>"
                $info += "⚠️ <strong>Wichtig:</strong> $deletePolicies aktive Lösch-Policies erkannt! E-Mails werden automatisch nach den definierten Zeiträumen gelöscht."
                $info += "</div>"
            }
        } else {
            $info += "<h3>   Retention Policies:</h3>"
            $info += "<div class='info-box'>ℹ️ Keine Retention Policies konfiguriert - E-Mails werden nicht automatisch gelöscht</div>"
        }
        
    } else {
        $info += "<div class='error info-box'>❌ MailStore API nicht verfügbar - Benutzer- und Profil-Informationen können nur über die API abgerufen werden</div>"
    }
    
    return $info
}
  
function Get-NetworkConfiguration {
    Write-Log "Sammle Netzwerk-Konfiguration..."
    
    $networkInfo = "<h2>   Netzwerk-Konfiguration</h2>"
    
    try {
        # Netzwerkadapter
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        $networkInfo += "<h3>Aktive Netzwerkadapter:</h3><table><tr><th>Name</th><th>Interface</th><th>Speed</th><th>MAC Address</th></tr>"
        
        foreach ($adapter in $adapters) {
            $speed = "Unbekannt"
            try {
                if ($adapter.LinkSpeed -and $adapter.LinkSpeed -is [int64]) {
                    $speed = "$([math]::Round($adapter.LinkSpeed / 1MB, 0)) Mbps"
                } elseif ($adapter.LinkSpeed) {
                    $speed = $adapter.LinkSpeed.ToString()
                }
            } catch {
                $speed = "Nicht verfügbar"
            }
            $networkInfo += "<tr><td>$($adapter.Name)</td><td>$($adapter.InterfaceDescription)</td><td>$speed</td><td>$($adapter.MacAddress)</td></tr>"
        }
        $networkInfo += "</table>"
        
        # IP-Konfiguration
        $ipConfigs = Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" -and $_.IPAddress -ne "127.0.0.1" }
        $networkInfo += "<h3>IP-Konfiguration:</h3><table><tr><th>Interface</th><th>IP-Adresse</th><th>Subnet</th></tr>"
        
        foreach ($ip in $ipConfigs) {
            try {
                $interface = (Get-NetAdapter -InterfaceIndex $ip.InterfaceIndex -ErrorAction SilentlyContinue).Name
                if (-not $interface) { $interface = "Unbekannt" }
                $networkInfo += "<tr><td>$interface</td><td>$($ip.IPAddress)</td><td>/$($ip.PrefixLength)</td></tr>"
            } catch {
                $networkInfo += "<tr><td>Fehler</td><td>$($ip.IPAddress)</td><td>/$($ip.PrefixLength)</td></tr>"
            }
        }
        $networkInfo += "</table>"
        
    } catch {
        $networkInfo += "<div class='error info-box'>❌ Netzwerk-Konfiguration konnte nicht abgerufen werden</div>"
    }
    
    return $networkInfo
}
  
function Get-DiskSpace {
    Write-Log "Analysiere Festplattenspeicher..."
    
    $diskInfo = "<h2>   Festplattenspeicher</h2>"
    
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $diskInfo += "<table><tr><th>Laufwerk</th><th>Label</th><th>Größe</th><th>Belegt</th><th>Frei</th><th>% Frei</th><th>Status</th></tr>"
    
    foreach ($disk in $disks) {
        $totalGB = [math]::Round($disk.Size / 1GB, 2)
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $usedGB = $totalGB - $freeGB
        $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        
        $status = if ($freePercent -lt 10) { "   Kritisch" } elseif ($freePercent -lt 20) { "   Warnung" } else { "   OK" }
        
        $diskInfo += "<tr><td>$($disk.DeviceID)</td><td>$($disk.VolumeName)</td><td>$totalGB GB</td><td>$usedGB GB</td><td>$freeGB GB</td><td>$freePercent%</td><td>$status</td></tr>"
    }
    $diskInfo += "</table>"
    
    return $diskInfo
}
  
function Get-PerformanceData {
    if (-not $IncludePerformanceData) {
        return ""
    }
    
    Write-Log "Sammle Performance-Daten..."
    
    $perfInfo = "<h2>   Performance-Daten</h2>"
    
    try {
        # CPU Auslastung
        $cpuUsage = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        
        # Memory Auslastung
        $totalRAM = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
        $freeRAM = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory * 1024
        $usedRAMPercent = [math]::Round((($totalRAM - $freeRAM) / $totalRAM) * 100, 1)
        
        $perfInfo += "<table><tr><th>Metrik</th><th>Wert</th><th>Status</th></tr>"
        $perfInfo += "<tr><td>CPU Auslastung</td><td>$cpuUsage%</td><td>$(if($cpuUsage -gt 80){'   Hoch'}elseif($cpuUsage -gt 60){'   Mittel'}else{'   Normal'})</td></tr>"
        $perfInfo += "<tr><td>RAM Auslastung</td><td>$usedRAMPercent%</td><td>$(if($usedRAMPercent -gt 80){'   Hoch'}elseif($usedRAMPercent -gt 60){'   Mittel'}else{'   Normal'})</td></tr>"
        $perfInfo += "</table>"
        
    } catch {
        $perfInfo += "<div class='error info-box'>❌ Performance-Daten konnten nicht abgerufen werden</div>"
    }
    
    return $perfInfo
}
  
# Hauptfunktion
function Generate-MailStoreDocumentation {
    Write-Log "Starte MailStore Dokumentation..."
    Write-Log "Ausgabedatei: $OutputPath"
    
    # MailStore API initialisieren
    $apiInitialized = Initialize-MailStoreAPI
    
    if ($apiInitialized) {
        Write-Log "MailStore API erfolgreich initialisiert - Detaillierte Informationen verfügbar"
    } else {
        Write-Log "MailStore API nicht verfügbar - Fallback auf Systemanalyse" "WARN"
    }
    
    # Alle Informationen sammeln
    $content = ""
    $content += Get-SystemInfo
    $content += Get-MailStoreServices
    $content += Get-MailStoreInstallation
    $content += Get-MailStoreConfiguration
    $content += Get-MailStoreArchives
    $content += Get-MailStoreFolderStructure
    $content += Get-MailStoreUsersAndProfiles
    $content += Get-NetworkConfiguration
    $content += Get-DiskSpace
    $content += Get-PerformanceData
    
    # HTML generieren
    $finalHtml = $htmlTemplate -replace "##CONTENT##", $content
    
    # Ausgabeverzeichnis erstellen falls nötig
    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # HTML-Datei schreiben
    try {
        $finalHtml | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Log "Dokumentation erfolgreich erstellt: $OutputPath" "INFO"
        
        # Datei öffnen
        if (Test-Path $OutputPath) {
            $fileSize = [math]::Round((Get-Item $OutputPath).Length / 1KB, 2)
            Write-Log "Dateigröße: $fileSize KB" "INFO"
            
            $openFile = Read-Host "Möchten Sie die Dokumentation jetzt öffnen? (J/N)"
            if ($openFile -eq "J" -or $openFile -eq "j" -or $openFile -eq "Y" -or $openFile -eq "y") {
                Start-Process $OutputPath
            }
        }
        
    } catch {
        Write-Log "Fehler beim Schreiben der Datei: $($_.Exception.Message)" "ERROR"
    }
}
  
# Script ausführen
try {
    # Parameter-Validierung und Hilfe
    if ($args -contains "-help" -or $args -contains "-?" -or $args -contains "/help" -or $args -contains "/?") {
        Write-Host @"
  
MailStore Dokumentations-Script v2.1
====================================
  
VERWENDUNG:
    .\MailStore-Documentation.ps1 [Parameter]
  
PARAMETER:
    -OutputPath <Pfad>              HTML-Ausgabedatei
    -MailStoreServerPath <Pfad>     MailStore Installation-Pfad
    -MailStoreServer <Server>       MailStore Server Hostname (Standard: localhost)
    -MailStorePort <Port>           MailStore API Port (Standard: 8463)
    -MailStoreUsername <User>       MailStore Admin Username (Standard: admin)
    -MailStorePassword <Passwort>   MailStore Admin Passwort
    -APIWrapperPath <Pfad>          Pfad zum MailStore PowerShell API Wrapper
    -IncludePerformanceData         Fügt Performance-Metriken hinzu
    -UseAPIOnly                     Verwendet nur MailStore API
  
BEISPIELE:
    .\MailStore-Documentation.ps1
    .\MailStore-Documentation.ps1 -MailStorePassword "MeinPasswort"
    .\MailStore-Documentation.ps1 -APIWrapperPath "C:\Scripts\API-Wrapper\MS.PS.Lib.psd1"
  
"@ -ForegroundColor Green
        exit
    }
    
    Generate-MailStoreDocumentation
} catch {
    Write-Log "Unerwarteter Fehler: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
}
  
Write-Log "Script beendet." 

