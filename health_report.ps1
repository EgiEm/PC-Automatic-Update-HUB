# health_report.ps1 - Weekly PC Health Report Generator
# Generates a self-contained HTML report and opens it in the default browser.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$reportDate = Get-Date -Format "yyyy-MM-dd"
$reportTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportFile = Join-Path $PSScriptRoot "PC_Health_Report_$reportDate.html"

Write-Host "Collecting system data..." -ForegroundColor Cyan

# ── 1. SYSTEM OVERVIEW ──
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$hostname = $cs.Name
$osVersion = $os.Caption + " (Build " + $os.BuildNumber + ")"
$bootTime = $os.LastBootUpTime
$uptime = (Get-Date) - $bootTime
$uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

# ── 2. CPU STATUS ──
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuName = $cpu.Name.Trim()
$cpuCores = $cpu.NumberOfCores
$cpuThreads = $cpu.NumberOfLogicalProcessors
$cpuLoad = $cpu.LoadPercentage
if (-not $cpuLoad) { $cpuLoad = 0 }

# ── 3. GPU STATUS ──
$gpuName = "N/A"
$gpuDriver = "N/A"
$gpuTemp = "N/A"
$gpuUtil = "N/A"
$gpuVramTotal = "N/A"
$gpuVramUsed = "N/A"

$gpuWmi = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
if ($gpuWmi) { $gpuName = $gpuWmi.Name }

if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $smiCsv = nvidia-smi --query-gpu=driver_version,temperature.gpu,utilization.gpu,memory.total,memory.used --format=csv,noheader,nounits 2>$null
    if ($smiCsv) {
        $parts = $smiCsv.Trim() -split ",\s*"
        if ($parts.Count -ge 5) {
            $gpuDriver = $parts[0]
            $gpuTemp   = $parts[1] + " C"
            $gpuUtil   = $parts[2] + "%"
            $gpuVramTotal = [Math]::Round([double]$parts[3] / 1024, 1).ToString() + " GB"
            $gpuVramUsed  = [Math]::Round([double]$parts[4] / 1024, 2).ToString() + " GB"
        }
    }
}

# ── 4. RAM USAGE ──
$totalRamGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$freeRamGB  = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedRamGB  = [Math]::Round($totalRamGB - $freeRamGB, 1)
$ramPercent = [Math]::Round(($usedRamGB / $totalRamGB) * 100, 1)

# ── 5. DISK HEALTH ──
$drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

$diskCards = ""
foreach ($d in $drives) {
    $totalGB = [Math]::Round($d.Size / 1GB, 1)
    $freeGB  = [Math]::Round($d.FreeSpace / 1GB, 1)
    $usedGB  = [Math]::Round($totalGB - $freeGB, 1)
    $pct     = if ($totalGB -gt 0) { [Math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

    $barColor = if ($pct -lt 70) { "#00d2ff" } elseif ($pct -lt 85) { "#f5a623" } else { "#ff4757" }

    $diskCards += @"
<div class="mini-card">
  <div class="mini-header">Drive $($d.DeviceID)</div>
  <div class="mini-body">
    <div class="stat-row"><span>Total</span><span>$totalGB GB</span></div>
    <div class="stat-row"><span>Used</span><span>$usedGB GB</span></div>
    <div class="stat-row"><span>Free</span><span>$freeGB GB</span></div>
    <div class="bar-bg"><div class="bar-fill" style="width:$pct%;background:$barColor;"></div></div>
    <div class="stat-row"><span>Usage</span><span style="color:$barColor;font-weight:700;">$pct%</span></div>
  </div>
</div>
"@
}

# Physical disk health info
$diskHealthRows = ""
if ($physicalDisks) {
    foreach ($pd in $physicalDisks) {
        $sizeGB = [Math]::Round($pd.Size / 1GB, 0)
        $healthColor = if ($pd.HealthStatus -eq "Healthy") { "#2ed573" } else { "#ff4757" }
        $diskHealthRows += "<tr><td>$($pd.FriendlyName)</td><td>$($pd.MediaType)</td><td>$sizeGB GB</td><td style='color:$healthColor;font-weight:700;'>$($pd.HealthStatus)</td></tr>"
    }
}

# ── 6. TOP 10 PROCESSES ──
$topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
$procRows = ""
$rank = 1
foreach ($p in $topProcs) {
    $memMB = [Math]::Round($p.WorkingSet64 / 1MB, 1)
    $procRows += "<tr><td>$rank</td><td>$($p.ProcessName)</td><td>$($p.Id)</td><td>$memMB MB</td></tr>"
    $rank++
}

# ── 7. NETWORK STATUS ──
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
$netRows = ""
foreach ($a in $adapters) {
    $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    if (-not $ip) { $ip = "N/A" }
    $speed = if ($a.LinkSpeed) { $a.LinkSpeed } else { "N/A" }
    $netRows += "<tr><td>$($a.Name)</td><td>$ip</td><td>$speed</td></tr>"
}

# Ping tests
$pingGoogle = "Timeout"
$pingSteam  = "Timeout"
try {
    $pg = Test-Connection -ComputerName "google.com" -Count 1 -ErrorAction Stop
    $pingGoogle = "$([Math]::Round($pg.ResponseTime, 0)) ms"
} catch {}
try {
    $ps = Test-Connection -ComputerName "steamcommunity.com" -Count 1 -ErrorAction Stop
    $pingSteam = "$([Math]::Round($ps.ResponseTime, 0)) ms"
} catch {}

# ── 8. STARTUP PROGRAMS ──
$startupPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
)
$startupRows = ""
foreach ($path in $startupPaths) {
    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
    if ($items) {
        $props = $items.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
        foreach ($prop in $props) {
            $startupRows += "<tr><td>$($prop.Name)</td><td style='word-break:break-all;max-width:500px;'>$($prop.Value)</td></tr>"
        }
    }
}

# ── RAM bar color ──
$ramBarColor = if ($ramPercent -lt 70) { "#00d2ff" } elseif ($ramPercent -lt 85) { "#f5a623" } else { "#ff4757" }

# ── CPU bar color ──
$cpuBarColor = if ($cpuLoad -lt 50) { "#2ed573" } elseif ($cpuLoad -lt 80) { "#f5a623" } else { "#ff4757" }

# ── BUILD HTML ──
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PC Health Report - $reportDate</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    background: #0f0f1a;
    color: #e0e0e0;
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    padding: 30px 20px;
    min-height: 100vh;
  }
  .container { max-width: 1100px; margin: 0 auto; }
  .report-header {
    text-align: center;
    padding: 30px 20px;
    margin-bottom: 30px;
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
    border-radius: 16px;
    border: 1px solid #2a2a4a;
  }
  .report-header h1 {
    font-size: 28px;
    background: linear-gradient(90deg, #00d2ff, #3a7bd5);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    margin-bottom: 8px;
  }
  .report-header p { color: #8892b0; font-size: 14px; }

  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 20px; margin-bottom: 20px; }
  .grid-full { grid-template-columns: 1fr; }

  .card {
    background: #1a1a2e;
    border-radius: 14px;
    border: 1px solid #2a2a4a;
    overflow: hidden;
    transition: transform 0.2s;
  }
  .card:hover { transform: translateY(-2px); box-shadow: 0 8px 30px rgba(0,0,0,0.3); }
  .card-header {
    padding: 14px 20px;
    font-size: 15px;
    font-weight: 700;
    letter-spacing: 0.5px;
    text-transform: uppercase;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .card-body { padding: 20px; }

  .h-system   .card-header { background: linear-gradient(135deg, #0f3460, #16213e); color: #00d2ff; }
  .h-cpu      .card-header { background: linear-gradient(135deg, #1b4332, #2d6a4f); color: #52b788; }
  .h-gpu      .card-header { background: linear-gradient(135deg, #3d0066, #5a189a); color: #c77dff; }
  .h-ram      .card-header { background: linear-gradient(135deg, #b45309, #78350f); color: #fbbf24; }
  .h-disk     .card-header { background: linear-gradient(135deg, #0e4429, #006d32); color: #2ed573; }
  .h-proc     .card-header { background: linear-gradient(135deg, #7f1d1d, #991b1b); color: #fca5a5; }
  .h-net      .card-header { background: linear-gradient(135deg, #1e3a5f, #0d47a1); color: #90caf9; }
  .h-startup  .card-header { background: linear-gradient(135deg, #4a1942, #6b2fa0); color: #e1bee7; }

  .stat-row { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #2a2a4a; font-size: 14px; }
  .stat-row:last-child { border-bottom: none; }
  .stat-row span:first-child { color: #8892b0; }
  .stat-row span:last-child { color: #e0e0e0; font-weight: 600; }

  .bar-bg { background: #2a2a4a; border-radius: 8px; height: 12px; margin: 10px 0; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 8px; transition: width 0.5s ease; }

  .mini-card { background: #16213e; border-radius: 10px; padding: 16px; border: 1px solid #2a2a4a; }
  .mini-header { font-weight: 700; color: #2ed573; margin-bottom: 10px; font-size: 15px; }
  .mini-body .stat-row { font-size: 13px; }
  .disk-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin-bottom: 16px; }

  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; padding: 10px 12px; background: #16213e; color: #8892b0; font-weight: 600; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; }
  td { padding: 9px 12px; border-bottom: 1px solid #2a2a4a; }
  tr:hover td { background: #16213e; }

  .footer {
    text-align: center;
    padding: 20px;
    margin-top: 30px;
    color: #4a5568;
    font-size: 12px;
    border-top: 1px solid #2a2a4a;
  }
  .ping-badge {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 13px;
    font-weight: 600;
  }
  .ping-ok   { background: #064e3b; color: #2ed573; }
  .ping-warn { background: #78350f; color: #fbbf24; }
  .ping-fail { background: #7f1d1d; color: #ff4757; }
</style>
</head>
<body>
<div class="container">

  <div class="report-header">
    <h1>PC Health Report</h1>
    <p>Generated on $reportTime</p>
  </div>

  <div class="grid">

    <!-- System Overview -->
    <div class="card h-system">
      <div class="card-header">System Overview</div>
      <div class="card-body">
        <div class="stat-row"><span>Hostname</span><span>$hostname</span></div>
        <div class="stat-row"><span>OS</span><span>$osVersion</span></div>
        <div class="stat-row"><span>Uptime</span><span>$uptimeStr</span></div>
        <div class="stat-row"><span>Report Date</span><span>$reportTime</span></div>
      </div>
    </div>

    <!-- CPU -->
    <div class="card h-cpu">
      <div class="card-header">CPU Status</div>
      <div class="card-body">
        <div class="stat-row"><span>Model</span><span>$cpuName</span></div>
        <div class="stat-row"><span>Cores / Threads</span><span>$cpuCores / $cpuThreads</span></div>
        <div class="stat-row"><span>Current Load</span><span style="color:$cpuBarColor;font-weight:700;">$cpuLoad%</span></div>
        <div class="bar-bg"><div class="bar-fill" style="width:$cpuLoad%;background:$cpuBarColor;"></div></div>
      </div>
    </div>

    <!-- GPU -->
    <div class="card h-gpu">
      <div class="card-header">GPU Status</div>
      <div class="card-body">
        <div class="stat-row"><span>Model</span><span>$gpuName</span></div>
        <div class="stat-row"><span>Driver</span><span>$gpuDriver</span></div>
        <div class="stat-row"><span>Temperature</span><span>$gpuTemp</span></div>
        <div class="stat-row"><span>Utilization</span><span>$gpuUtil</span></div>
        <div class="stat-row"><span>VRAM Used / Total</span><span>$gpuVramUsed / $gpuVramTotal</span></div>
      </div>
    </div>

    <!-- RAM -->
    <div class="card h-ram">
      <div class="card-header">RAM Usage</div>
      <div class="card-body">
        <div class="stat-row"><span>Total</span><span>$totalRamGB GB</span></div>
        <div class="stat-row"><span>Used</span><span>$usedRamGB GB</span></div>
        <div class="stat-row"><span>Free</span><span>$freeRamGB GB</span></div>
        <div class="stat-row"><span>Usage</span><span style="color:$ramBarColor;font-weight:700;">$ramPercent%</span></div>
        <div class="bar-bg"><div class="bar-fill" style="width:$ramPercent%;background:$ramBarColor;"></div></div>
      </div>
    </div>

  </div>

  <!-- Disk Health -->
  <div class="grid grid-full">
    <div class="card h-disk">
      <div class="card-header">Disk Health</div>
      <div class="card-body">
        <div class="disk-grid">
          $diskCards
        </div>
        <table>
          <tr><th>Disk Name</th><th>Type</th><th>Size</th><th>Health</th></tr>
          $diskHealthRows
        </table>
      </div>
    </div>
  </div>

  <!-- Top 10 Processes -->
  <div class="grid grid-full">
    <div class="card h-proc">
      <div class="card-header">Top 10 Processes by Memory</div>
      <div class="card-body">
        <table>
          <tr><th>#</th><th>Process</th><th>PID</th><th>Memory</th></tr>
          $procRows
        </table>
      </div>
    </div>
  </div>

  <div class="grid">

    <!-- Network -->
    <div class="card h-net">
      <div class="card-header">Network Status</div>
      <div class="card-body">
        <table>
          <tr><th>Adapter</th><th>IP Address</th><th>Link Speed</th></tr>
          $netRows
        </table>
        <div style="margin-top:14px;">
          <div class="stat-row"><span>Ping google.com</span><span class="ping-badge $(if($pingGoogle -eq 'Timeout'){'ping-fail'}else{'ping-ok'})">$pingGoogle</span></div>
          <div class="stat-row"><span>Ping steamcommunity.com</span><span class="ping-badge $(if($pingSteam -eq 'Timeout'){'ping-fail'}else{'ping-ok'})">$pingSteam</span></div>
        </div>
      </div>
    </div>

    <!-- Startup Programs -->
    <div class="card h-startup">
      <div class="card-header">Startup Programs</div>
      <div class="card-body">
        <table>
          <tr><th>Name</th><th>Command</th></tr>
          $startupRows
        </table>
      </div>
    </div>

  </div>

  <div class="footer">
    PC Health Report &bull; Generated by health_report.ps1 &bull; $reportTime
  </div>

</div>
</body>
</html>
"@

# ── SAVE & OPEN ──
$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  [OK] Raporti u gjenerua me sukses!" -ForegroundColor Green
Write-Host "  Fajlli: $reportFile" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Start-Process $reportFile
