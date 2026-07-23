param(
    [switch]$Install
)

# Set console encoding to UTF-8 to support any special characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# If install switch is provided but session is not elevated, relaunch as Admin
if ($Install -and -not $isAdmin) {
    Write-Host "[!] Skripti kerkon privilegje Administratori per te instaluar perditesimet." -ForegroundColor Yellow
    Write-Host "Duke hapur nje dritare te re si Administrator... Ju lutem pranoni UAC prompt." -ForegroundColor Cyan
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSScriptRoot\pc_check.ps1`" -Install"
    Exit
}

if ($Install) {
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host "    DUKE SHKARKUAR DHE INSTALUAR PERDITESIMET     " -ForegroundColor Yellow -BackgroundColor DarkYellow
    Write-Host "==================================================" -ForegroundColor Yellow

    # Check if PSWindowsUpdate is installed, if not try to install it
    $mod = Get-Module -ListAvailable PSWindowsUpdate
    if (-not $mod) {
        Write-Host "Moduli PSWindowsUpdate nuk u gjet. Duke u instaluar..." -ForegroundColor Cyan
        try {
            # Enable TLS 1.2 for downloads
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            # Install Nuget provider if missing
            if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Write-Host "Duke instaluar NuGet Package Provider..." -ForegroundColor Gray
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
            }
            # Trust PSGallery
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            # Install module
            Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope CurrentUser -ErrorAction Stop
            Write-Host "[OK] Moduli PSWindowsUpdate u instalua me sukses!" -ForegroundColor Green
        } catch {
            Write-Host "[!] Gabim gjate instalimit te modulit: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Duke provuar instalimin me COM API si fallback..." -ForegroundColor Yellow
        }
    }

    # Verify again if module is available
    $mod = Get-Module -ListAvailable PSWindowsUpdate
    if ($mod) {
        Write-Host "Duke kontrolluar dhe instaluar permes PSWindowsUpdate..." -ForegroundColor Cyan
        try {
            # Download and Install all updates (including Microsoft Updates)
            # AcceptAll and AutoReboot:$false will download & install and wait for user restart
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -AutoReboot:$false
        } catch {
            Write-Host "[!] Gabim gjate instalimit me PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Duke kaluar ne COM API si fallback..." -ForegroundColor Yellow
            $mod = $null
        }
    }

    if (-not $mod) {
        # Fallback to COM API installation
        Write-Host "Duke perdorur COM API si fallback per instalim..." -ForegroundColor Cyan
        try {
            $UpdateSession = New-Object -ComObject Microsoft.Update.Session
            $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
            $UpdateSearcher.Online = $true
            
            Write-Host "Duke kerkuar..." -ForegroundColor Gray
            $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software'")
            
            if ($SearchResult.Updates.Count -gt 0) {
                Write-Host "U gjeten $($SearchResult.Updates.Count) perditesime per t'u instaluar." -ForegroundColor Gray
                
                # Create downloader
                $Downloader = $UpdateSession.CreateUpdateDownloader()
                $Downloader.Updates = $SearchResult.Updates
                Write-Host "Duke shkarkuar..." -ForegroundColor Yellow
                $DownloadResult = $Downloader.Download()
                
                # Create installer
                $Installer = $UpdateSession.CreateUpdateInstaller()
                $Installer.Updates = $SearchResult.Updates
                Write-Host "Duke instaluar..." -ForegroundColor Yellow
                $InstallResult = $Installer.Install()
                
                Write-Host "[OK] Instalimi perfundoi me status kodin: $($InstallResult.ResultCode)" -ForegroundColor Green
            } else {
                Write-Host "Nuk u gjet asnje perditesim per t'u instaluar." -ForegroundColor Green
            }
        } catch {
            Write-Host "[!] Gabim gjate instalimit me COM API: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nJu mund ta beni restart kompjuterin tani per te aplikuar ndryshimet." -ForegroundColor Cyan
    Read-Host "Shtypni Enter per te mbyllur kete dritare..."
    Exit
}

# ----------------- NORMAL SCAN MODE -----------------

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   SISTEMI I KONTROLLIT TE PERDITESIMEVE (PC)     " -ForegroundColor Cyan -BackgroundColor DarkCyan
Write-Host "==================================================" -ForegroundColor Cyan

# ----------------- 1. NVIDIA GPU DRIVER CHECK -----------------
Write-Host "`n[1] Duke kontrolluar NVIDIA GPU Driver..." -ForegroundColor Yellow
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
$nvidiaStatus = "N/A"
$currentVer = ""
$latestVer = ""

if ($gpu) {
    # Get current version from nvidia-smi if available, else from WMI
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $smi = nvidia-smi --query-gpu=driver_version --format=csv,noheader
        if ($smi) { $currentVer = $smi.Trim() }
    }
    if (-not $currentVer) {
        # Fallback to driver version from WMI (e.g. 32.0.16.1074 -> last 5 digits)
        $wmiVer = $gpu.DriverVersion
        if ($wmiVer -match "\.(\d+)\.(\d+)$") {
            $lastPart = $Matches[1] + $Matches[2]
            if ($lastPart.Length -ge 5) {
                $currentVer = $lastPart.Substring($lastPart.Length - 5)
                $currentVer = $currentVer.Substring(0, 3) + "." + $currentVer.Substring(3)
            }
        }
    }
    
    Write-Host "  Modeli: $($gpu.Name)" -ForegroundColor Gray
    Write-Host "  Versioni aktual: $currentVer" -ForegroundColor Gray
    
    # Query latest driver version from Nvidia API
    $searchName = $gpu.Name -replace "^NVIDIA ", ""
    $lookupUrl = "https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3"
    $downloadUrl = ""
    try {
        $xml = Invoke-RestMethod -Uri $lookupUrl
        $match = $xml.SelectNodes("//LookupValue") | Where-Object { $_.Name -like "*$searchName*" } | Select-Object -First 1
        if (-not $match) {
            # Fallback to generic search for RTX 5060 if name matching is too strict
            $match = $xml.SelectNodes("//LookupValue") | Where-Object { $_.Name -like "*RTX 5060*" } | Select-Object -First 1
        }
        if ($match) {
            $pfid = $match.Value
            $queryUrl = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&pfid=$pfid&osID=57&languageCode=1033&beta=0&isWHQL=1&dch=1"
            $driverResp = Invoke-RestMethod -Uri $queryUrl
            if ($driverResp.IDS.downloadInfo) {
                $latestVer = $driverResp.IDS.downloadInfo.Version
                $downloadUrl = $driverResp.IDS.downloadInfo.DownloadURL
            }
        }
    } catch {
        Write-Host "  [!] Nuk u mundesua marrja e versionit te fundit nga NVIDIA API: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    if ($latestVer) {
        Write-Host "  Versioni me i ri: $latestVer" -ForegroundColor Gray
        if ($currentVer -eq $latestVer) {
            Write-Host "  [OK] Driver-i i NVIDIA-s eshte i perditesuar!" -ForegroundColor Green
            $nvidiaStatus = "Up-to-date"
        } else {
            Write-Host "  [UPDATE] Ka perditesim te ri per NVIDIA GPU! ($latestVer)" -ForegroundColor Red
            Write-Host "  Shkarko nga: $downloadUrl" -ForegroundColor Cyan
            $nvidiaStatus = "Update Available ($latestVer)"
        }
    } else {
        Write-Host "  [?] Statusi i versionit nuk mund te krahasohej." -ForegroundColor Yellow
        $nvidiaStatus = "Unknown"
    }
} else {
    Write-Host "  [OK] Nuk u detektua kartele NVIDIA GPU." -ForegroundColor Green
}

# ----------------- 2. AMD CHIPSET / DRIVERS CHECK -----------------
Write-Host "`n[2] Duke kontrolluar AMD Chipset / Drivers..." -ForegroundColor Yellow
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Write-Host "  Procesori: $($cpu.Name)" -ForegroundColor Gray

$amdStatus = "N/A"
if ($cpu.Name -like "*AMD*") {
    # Check AMD Chipset software from Registry
    $amdUninstall = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*AMD Chipset*" -or $_.DisplayName -like "*AMD Software*" } | Select-Object DisplayName, DisplayVersion -First 1
    
    if ($amdUninstall) {
        Write-Host "  Paketa e instaluar: $($amdUninstall.DisplayName)" -ForegroundColor Gray
        Write-Host "  Versioni i instaluar: $($amdUninstall.DisplayVersion)" -ForegroundColor Gray
        $amdStatus = "Installed (v$($amdUninstall.DisplayVersion))"
    } else {
        Write-Host "  [!] Nuk u gjet pakete e instaluar 'AMD Chipset Software' ne regjister." -ForegroundColor Yellow
        $amdStatus = "Not found in registry"
    }
    
    # List core AMD Chipset drivers from Device Manager (PnP Signed Drivers)
    $amdPnp = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.Manufacturer -like "*AMD*" -and $_.DeviceName -match "GPIO|I2C|PCI|SATA|SMBus|System Management" }
    if ($amdPnp) {
        Write-Host "  Driver-at e AMD Chipset te detektuar:" -ForegroundColor Gray
        $amdPnp | Group-Object DeviceName | ForEach-Object {
            $drv = $_.Group[0]
            Write-Host "    - $($drv.DeviceName) (v$($drv.DriverVersion))" -ForegroundColor Gray
        }
    }
    Write-Host "  [OK] AMD Chipset drivers jane aktive dhe funksionale." -ForegroundColor Green
} else {
    Write-Host "  [OK] Nuk u detektua CPU AMD (nuka ka nevoje per AMD Chipset Drivers)." -ForegroundColor Green
}

# ----------------- 3. WINDOWS UPDATES CHECK -----------------
Write-Host "`n[3] Duke kontrolluar Windows Updates..." -ForegroundColor Yellow
$winUpdates = @()
$pswuInstalled = $false

# Check using PSWindowsUpdate if available
$mod = Get-Module -ListAvailable PSWindowsUpdate
if ($mod) {
    $pswuInstalled = $true
    try {
        Write-Host "  Duke perdorur modulin PSWindowsUpdate..." -ForegroundColor Gray
        $winUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop | Select-Object Title, KB, Size
    } catch {
        Write-Host "  [!] Gabim gjate perdorimit te PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
        $pswuInstalled = $false
    }
}

# Fallback to COM object if PSWindowsUpdate is not installed or failed
if (-not $pswuInstalled) {
    try {
        Write-Host "  Duke perdorur Microsoft.Update.Session COM API..." -ForegroundColor Gray
        $UpdateSession = New-Object -ComObject Microsoft.Update.Session
        $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
        $UpdateSearcher.Online = $true
        $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software'")
        foreach ($u in $SearchResult.Updates) {
            $winUpdates += [PSCustomObject]@{
                Title = $u.Title
                KB = ($u.KBArticleIDs -join ", ")
            }
        }
    } catch {
        Write-Host "  [!] Gabim gjate kerkimit permes COM API: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($winUpdates.Count -gt 0) {
    Write-Host "  Ka $($winUpdates.Count) perditesime te Windows-it ne pritje:" -ForegroundColor Red
    foreach ($upd in $winUpdates) {
        Write-Host "    - $($upd.Title) (KB: $($upd.KB))" -ForegroundColor Red
    }
    $winStatus = "$($winUpdates.Count) updates pending"
} else {
    Write-Host "  [OK] Windows-i eshte plotesisht i perditesuar!" -ForegroundColor Green
    $winStatus = "Up-to-date"
}

# ----------------- 4. WINGET APP UPGRADES CHECK -----------------
Write-Host "`n[4] Duke kontrolluar perditesimet e aplikacioneve permes Winget..." -ForegroundColor Yellow
$wingetUpgrades = @()
try {
    # Run winget upgrade
    $wingetOut = winget upgrade --accept-source-agreements --accept-package-agreements
    $lines = $wingetOut -split "\r?\n" | Where-Object { $_ -match "\S" }
    
    $headerIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "Name" -and $lines[$i] -match "Id" -and $lines[$i] -match "Version") {
            $headerIndex = $i
            break
        }
    }
    
    if ($headerIndex -ge 0 -and $headerIndex + 1 -lt $lines.Count) {
        $separator = $lines[$headerIndex + 1]
        $colIndices = @()
        $inDash = $false
        for ($j = 0; $j -lt $separator.Length; $j++) {
            $char = $separator[$j]
            if ($char -eq '-') {
                if (-not $inDash) {
                    $colIndices += $j
                    $inDash = $true
                }
            } else {
                $inDash = $false
            }
        }
        
        for ($i = $headerIndex + 2; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match "upgrades available" -or $line -match "No upgrades available" -or $line -match "----------------") {
                continue
            }
            if ($line.Length -lt $separator.Length) {
                $line = $line.PadRight($separator.Length)
            }
            
            $name = $line.Substring($colIndices[0], ($colIndices[1] - $colIndices[0])).Trim()
            $id = $line.Substring($colIndices[1], ($colIndices[2] - $colIndices[1])).Trim()
            $version = $line.Substring($colIndices[2], ($colIndices[3] - $colIndices[2])).Trim()
            $available = $line.Substring($colIndices[3], ($colIndices[4] - $colIndices[3])).Trim()
            
            if ($name -and $id) {
                $wingetUpgrades += [PSCustomObject]@{
                    Name = $name
                    Id = $id
                    Installed = $version
                    Available = $available
                }
            }
        }
    }
} catch {
    Write-Host "  [!] Gabim gjate kontrollit te Winget: $($_.Exception.Message)" -ForegroundColor Red
}

if ($wingetUpgrades.Count -gt 0) {
    Write-Host "  Ka $($wingetUpgrades.Count) aplikacione qe kane perditesime ne dispozicion:" -ForegroundColor Red
    foreach ($app in $wingetUpgrades) {
        Write-Host "    - $($app.Name) (v$($app.Installed) -> v$($app.Available))" -ForegroundColor Red
    }
    $appsStatus = "$($wingetUpgrades.Count) updates available"
} else {
    Write-Host "  [OK] Te gjitha aplikacionet e Winget jane te perditesuara!" -ForegroundColor Green
    $appsStatus = "Up-to-date"
}

# ----------------- SUMMARY REPORT -----------------
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "       PERMBLEDHJE E STATUSIT TE SISTEMIT         " -ForegroundColor Cyan -BackgroundColor DarkCyan
Write-Host "==================================================" -ForegroundColor Cyan

# NVIDIA status output
if ($gpu) {
    if ($nvidiaStatus -eq "Up-to-date") {
        Write-Host "  NVIDIA GPU Driver:    [ OK ] - Sistemi eshte i perditesuar ($currentVer)" -ForegroundColor Green
    } elseif ($nvidiaStatus -like "Update Available*") {
        Write-Host "  NVIDIA GPU Driver:    [ UPDATE ] - Ka perditesim te ri ($latestVer)" -ForegroundColor Red
    } else {
        Write-Host "  NVIDIA GPU Driver:    [ ? ] - Status i panjohur" -ForegroundColor Yellow
    }
} else {
    Write-Host "  NVIDIA GPU Driver:    [ N/A ] - Nuk u detektua kartele NVIDIA" -ForegroundColor Gray
}

# AMD status output
if ($cpu.Name -like "*AMD*") {
    if ($amdStatus -like "Installed*") {
        Write-Host "  AMD Chipset Software: [ OK ] - Instaluar ($amdStatus)" -ForegroundColor Green
    } else {
        Write-Host "  AMD Chipset Software: [ ! ] - Jo e instaluar ose nuk u gjet" -ForegroundColor Yellow
    }
} else {
    Write-Host "  AMD Chipset Software: [ N/A ] - Nuk aplikohet" -ForegroundColor Gray
}

# Windows Updates status output
if ($winStatus -eq "Up-to-date") {
    Write-Host "  Windows Updates:      [ OK ] - Sistemi eshte i perditesuar" -ForegroundColor Green
} else {
    Write-Host "  Windows Updates:      [ UPDATE ] - $winStatus" -ForegroundColor Red
}

# Winget apps status output
if ($appsStatus -eq "Up-to-date") {
    Write-Host "  Aplikacionet (Winget):[ OK ] - Te gjitha jane te perditesuara" -ForegroundColor Green
} else {
    Write-Host "  Aplikacionet (Winget):[ UPDATE ] - $appsStatus" -ForegroundColor Red
}
Write-Host "==================================================" -ForegroundColor Cyan
