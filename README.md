# PC Automatic Update & Hardware Monitor HUB

A collection of custom PowerShell automation scripts designed to scan, manage, install system updates, launch game updates, and monitor hardware temperatures/metrics in real time.

## Scripts & Services

### 1. PC Update Checker (`pc_check.ps1`)
*   **NVIDIA GPU Check**: Scans the system for the installed GPU, queries NVIDIA's official API for the latest Game Ready driver version, and compares it with the installed version.
*   **AMD Chipset Check**: Verifies if the AMD Chipset Software is installed, checks its version in the registry, and lists the active AMD PnP driver versions.
*   **Windows Updates**: Searches online for pending Windows OS and security updates.
*   **App Upgrades**: Lists all available third-party application upgrades via `winget`.
*   **Auto-Installation Mode**: Downloads and installs all pending updates automatically.

### 2. Steam Game Updater (`update_cs2.ps1`)
*   Checks if the Steam client is active (opens it if it's closed).
*   Triggers Steam's internal protocol to automatically download updates and launch **Counter-Strike 2 (AppID: 730)**.

### 3. Hardware Monitor & Temperature Check (`hardware_monitor.ps1`)
*   **RAM Usage**: Displays total, used, and free memory alongside a visual progress bar.
*   **GPU Metrics**: Live-monitors utilization and temperature of the NVIDIA RTX 5060 GPU using `nvidia-smi`.
*   **CPU Metrics**: Live-monitors utilization and core temperature of the AMD Ryzen 7 9800X3D CPU (integrates with LibreHardwareMonitor's JSON API).
*   **Overheating Alerts**: Warns you with red console alerts if CPU exceeds 85°C or GPU exceeds 80°C.

### 4. Weekly PC Health Report (`health_report.ps1`)
*   Generates a self-contained, dark-themed **HTML dashboard** showing a full snapshot of your PC's health.
*   **System Overview**: OS version, hostname, uptime since last restart.
*   **CPU & GPU Status**: Model, driver version, current temperature, utilization, and VRAM usage.
*   **RAM Usage**: Total/used/free with a color-coded progress bar.
*   **Disk Health**: Per-drive usage bars with SSD/HDD health status from `Get-PhysicalDisk`.
*   **Top 10 Processes**: A ranked table of the most memory-hungry processes running.
*   **Network Status**: Active adapters, IP addresses, link speed, and ping tests to Google and Steam.
*   **Startup Programs**: Lists everything that auto-starts with Windows.
*   The report is saved as `PC_Health_Report_YYYY-MM-DD.html` and opens automatically in your browser.

---

## How to Run

Open **PowerShell** (some scripts require Administrator privileges as noted below) and execute the commands:

### Skanimi i Përditësimeve (Check Updates)
To check for updates without installing anything:
```powershell
powershell -ExecutionPolicy Bypass -File .\pc_check.ps1
```

### Instalimi i Përditësimeve (Install Updates)
To download and install all Windows updates automatically (runs as **Administrator**):
```powershell
powershell -ExecutionPolicy Bypass -File .\pc_check.ps1 -Install
```

### Përditësimi i CS2 (Update Counter-Strike 2)
To queue the update and launch CS2 in Steam:
```powershell
powershell -ExecutionPolicy Bypass -File .\update_cs2.ps1
```

### Monitorimi Live i Temperaturave (Live Hardware Monitor)
To start the live dashboard checking temperatures and RAM usage:
1. Download **[LibreHardwareMonitor](https://librehardwaremonitor.github.io/)** (free/open-source).
2. Open it, click **Options** in the top menu, and select **"Run Web Server"**.
3. Run this command in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\hardware_monitor.ps1
```

### Raporti Javor i Shëndetit (Weekly PC Health Report)
To generate the full HTML health dashboard and open it in your browser:
```powershell
powershell -ExecutionPolicy Bypass -File .\health_report.ps1
```

---

> [!WARNING]  
> **IMPORTANT NOTE:** These scripts are tailored and optimized specifically for my personal PC hardware configuration:
> *   **CPU**: AMD Ryzen 7 9800X3D
> *   **GPU**: NVIDIA GeForce RTX 5060
> 
> Running these scripts on systems with different hardware (e.g., Intel CPUs, AMD/Intel GPUs, or different motherboard chipsets) might fail, skip checks, or not function correctly!
