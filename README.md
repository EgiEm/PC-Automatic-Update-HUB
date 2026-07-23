# PC Automatic Update HUB

A collection of custom PowerShell automation scripts designed to scan, manage, and install system updates and game updates.

## Scripts & Services

### 1. PC Update Checker (`pc_check.ps1`)
*   **NVIDIA GPU Check**: Scans the system for the installed GPU, queries NVIDIA's official API for the latest Game Ready driver version, and compares it with the installed version.
*   **AMD Chipset Check**: Verifies if the AMD Chipset Software is installed, checks its version in the registry, and list the active AMD PnP driver versions.
*   **Windows Updates**: Searches online for pending Windows OS and security updates.
*   **App Upgrades**: Lists all available third-party application upgrades via `winget`.
*   **Auto-Installation Mode**: Running `.\pc_check.ps1 -Install` will automatically request Administrator permissions (UAC elevation) and install all pending updates.

### 2. Steam Game Updater (`update_cs2.ps1`)
*   Checks if the Steam client is active.
*   Triggers Steam's internal protocol to automatically download updates and launch **Counter-Strike 2 (AppID: 730)**.

---

> [!WARNING]  
> **IMPORTANT NOTE:** These scripts are tailored and optimized specifically for my personal PC hardware configuration:
> *   **CPU**: AMD Ryzen 7 9800X3D
> *   **GPU**: NVIDIA GeForce RTX 5060
> 
> Running these scripts on systems with different hardware (e.g., Intel CPUs, AMD/Intel GPUs, or different motherboard chipsets) might fail, skip checks, or not function correctly!
