# Set console encoding to UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$thresholdCpu = 85  # Alert if CPU exceeds 85°C
$thresholdGpu = 80  # Alert if GPU exceeds 80°C

# Helper to clear terminal screen
function Clear-Screen {
    try {
        [Console]::Clear()
    } catch {
        # Fallback if console host is not active
    }
}

Write-Host "Duke nisur Kontrolluesin e Nxehtesise..." -ForegroundColor Yellow

# Loop to refresh dashboard every 2 seconds
while ($true) {
    Clear-Screen
    
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "       KONTROLLUESI I NXHETESISE & HARDUERIT      " -ForegroundColor Cyan -BackgroundColor DarkCyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Shtypni Ctrl + C per te ndalur monitorimin live.`n" -ForegroundColor Gray

    # --- 1. SYSTEM RAM USAGE ---
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRam = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeRam = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedRam = [Math]::Round($totalRam - $freeRam, 1)
    $ramPercent = [Math]::Round(($usedRam / $totalRam) * 100, 1)
    
    # --- 2. CPU LOAD ---
    $cpuLoad = (Get-CimInstance Win32_Processor).LoadPercentage
    
    # --- 3. HARDWARE TEMPERATURE DETAILS ---
    $cpuTemp = $null
    $gpuTemp = $null
    $gpuLoad = $null
    $lhmRunning = $false

    # Try to query LibreHardwareMonitor Web Server (localhost:8085)
    $lhmUrl = "http://localhost:8085/data.json"
    try {
        $lhmData = Invoke-RestMethod -Uri $lhmUrl -TimeoutSec 1 -ErrorAction Stop
        $lhmRunning = $true
        
        # Recursive function to find sensor values in LHM JSON structure
        function Find-Sensor($node, $namePattern, $type) {
            if ($node.Text -like $namePattern -and $node.ImageURL -like "*$type*") {
                return $node.Value
            }
            if ($node.Children) {
                foreach ($child in $node.Children) {
                    $val = Find-Sensor $child $namePattern $type
                    if ($val) { return $val }
                }
            }
            return $null
        }

        # Find CPU Temp (Ryzen 9800X3D)
        $cpuTempRaw = Find-Sensor $lhmData.Children[0] "*Core*" "temperature"
        if ($cpuTempRaw -and $cpuTempRaw -match "(\d+(\.\d+)?)") {
            $cpuTemp = [double]$Matches[1]
        }

        # Find GPU Temp
        $gpuTempRaw = Find-Sensor $lhmData.Children[0] "*GPU Core*" "temperature"
        if ($gpuTempRaw -and $gpuTempRaw -match "(\d+(\.\d+)?)") {
            $gpuTemp = [double]$Matches[1]
        }
    } catch {
        # LibreHardwareMonitor is not running or web server is not enabled
        $lhmRunning = $false
    }

    # Fallback for GPU Temp using nvidia-smi if LHM is not running
    if (-not $gpuTemp -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        $smiOut = nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null
        if ($smiOut -and $smiOut -match "(\d+),\s*(\d+)") {
            $gpuTemp = [double]$Matches[1]
            $gpuLoad = [double]$Matches[2]
        }
    }

    # --- DISPLAY METRICS ---
    
    # CPU Section
    Write-Host "1. PROCESSOR (CPU):" -ForegroundColor Yellow
    Write-Host "   Modeli:     AMD Ryzen 7 9800X3D" -ForegroundColor Gray
    Write-Host "   Perdorimi:  $cpuLoad %" -ForegroundColor Gray
    if ($cpuTemp) {
        $color = "Green"
        if ($cpuTemp -ge $thresholdCpu) { $color = "Red" }
        elseif ($cpuTemp -ge ($thresholdCpu - 15)) { $color = "Yellow" }
        Write-Host "   Temperatura: " -NoNewline -ForegroundColor Gray
        Write-Host "$cpuTemp °C" -ForegroundColor $color
    } else {
        Write-Host "   Temperatura: [!] Ndiz LibreHardwareMonitor per te pare temp e CPU" -ForegroundColor Yellow
    }

    # GPU Section
    Write-Host "`n2. GRAPHICS CARD (GPU):" -ForegroundColor Yellow
    Write-Host "   Modeli:     NVIDIA GeForce RTX 5060" -ForegroundColor Gray
    if ($gpuLoad) {
        Write-Host "   Perdorimi:  $gpuLoad %" -ForegroundColor Gray
    }
    if ($gpuTemp) {
        $color = "Green"
        if ($gpuTemp -ge $thresholdGpu) { $color = "Red" }
        elseif ($gpuTemp -ge ($thresholdGpu - 15)) { $color = "Yellow" }
        Write-Host "   Temperatura: " -NoNewline -ForegroundColor Gray
        Write-Host "$gpuTemp °C" -ForegroundColor $color
    } else {
        Write-Host "   Temperatura: N/A" -ForegroundColor Gray
    }

    # RAM Section
    Write-Host "`n3. MEMORY (RAM):" -ForegroundColor Yellow
    Write-Host "   Totale:     $totalRam GB" -ForegroundColor Gray
    Write-Host "   E perdorur:  $usedRam GB ($ramPercent %)" -ForegroundColor Gray
    
    # RAM progress bar
    $barLength = 20
    $filledLength = [Math]::Round(($ramPercent / 100) * $barLength)
    $emptyLength = $barLength - $filledLength
    $bar = "[" + ("#" * $filledLength) + ("-" * $emptyLength) + "]"
    Write-Host "   Statusi:    $bar" -ForegroundColor Gray

    # --- ALERT MESSAGES ---
    Write-Host "`n--------------------------------------------------" -ForegroundColor Cyan
    Write-Host "                     ALERTE                       " -ForegroundColor Cyan -BackgroundColor DarkCyan
    Write-Host "--------------------------------------------------" -ForegroundColor Cyan

    $hasAlert = $false
    if ($cpuTemp -and $cpuTemp -ge $thresholdCpu) {
        Write-Host "  [WARNING] CPU eshte shume i nxehte ($cpuTemp °C)! Kontrollo ftohjen." -ForegroundColor Red
        $hasAlert = $true
    }
    if ($gpuTemp -and $gpuTemp -ge $thresholdGpu) {
        Write-Host "  [WARNING] GPU eshte shume i nxehte ($gpuTemp °C)! Kontrollo ventilatoret." -ForegroundColor Red
        $hasAlert = $true
    }
    
    if (-not $hasAlert) {
        Write-Host "  [OK] Temperaturat dhe ngarkesa jane brenda normave te lejuara." -ForegroundColor Green
    }

    if (-not $lhmRunning) {
        Write-Host "`n* Shenim: Per te aktivizuar leximin e temperaturave te CPU (Ryzen 9800X3D):" -ForegroundColor Gray
        Write-Host "  1. Shkarko LibreHardwareMonitor." -ForegroundColor Gray
        Write-Host "  2. Hap Options -> Run Web Server ne program." -ForegroundColor Gray
    }

    Start-Sleep -Seconds 2
}
