# Set console encoding to UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "       PERDITESIMI I COUNTER-STRIKE 2 (STEAM)     " -ForegroundColor Cyan -BackgroundColor DarkCyan
Write-Host "==================================================" -ForegroundColor Cyan

Write-Host "`n[1] Duke kontrolluar nese Steam eshte i hapur..." -ForegroundColor Yellow
$steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue

if ($steamProcess) {
    Write-Host "  [OK] Steam eshte i hapur (PID: $($steamProcess.Id))." -ForegroundColor Green
    Write-Host "  Duke nisur perditesimin dhe hapjen e CS2..." -ForegroundColor Cyan
    
    # Trigger Steam to run and update CS2 (AppID: 730)
    Start-Process "steam://run/730"
    Write-Host "  [OK] Komanda u dergua me sukses te Steam! Kontrollo dritaren e shkarkimeve ne Steam." -ForegroundColor Green
} else {
    Write-Host "  [!] Steam nuk eshte i hapur!" -ForegroundColor Red
    Write-Host "  Duke hapur aplikacionin Steam..." -ForegroundColor Cyan
    
    # Try to launch Steam
    Start-Process "steam://run/730"
    Write-Host "  [OK] Steam u nis. Kontrollo dritaren e shkarkimeve pasi te hapet Steam." -ForegroundColor Green
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Shtypni Enter per te mbyllur kete dritare..."
Read-Host
