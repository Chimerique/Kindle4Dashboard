# Script de vérification USBNetwork installé
# À exécuter après installation sur Kindle

# Auto-élévation si pas admin (nécessaire pour New-NetIPAddress)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Relancement en administrateur..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Vérification installation USBNetwork...`n" -ForegroundColor Yellow

# Détecter l'adaptateur RNDIS par description (indépendant du nom Ethernet X)
$rndisAdapter = Get-NetAdapter | Where-Object {
    ($_.InterfaceDescription -match "RNDIS|USB Ethernet") -and $_.Status -eq "Up"
} | Select-Object -First 1

if ($rndisAdapter) {
    Write-Host "[OK] Adaptateur RNDIS détecté : $($rndisAdapter.Name) ($($rndisAdapter.InterfaceDescription))" -ForegroundColor Green
    # Configurer l'IP si pas déjà fait
    $existingIP = Get-NetIPAddress -InterfaceAlias $rndisAdapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -like "192.168.15.*" }
    if (-not $existingIP) {
        Write-Host "Configuration IP 192.168.15.201 sur $($rndisAdapter.Name)..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $rndisAdapter.Name -IPAddress "192.168.15.201" -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep 2
    } else {
        Write-Host "[OK] IP déjà configurée : $($existingIP.IPAddress)" -ForegroundColor Green
    }
} else {
    Write-Host "[WARN] Aucun adaptateur RNDIS Up détecté - Kindle branché ?" -ForegroundColor Yellow
}

# Vérifier Kindle (USB Mass Storage mode)
if (Test-Path D:\) {
    Write-Host "[OK] D:\ monté (mode USB Mass Storage)" -ForegroundColor Green
    if (Test-Path D:\usbnet) {
        Write-Host "[OK] D:\usbnet\ trouvé" -ForegroundColor Green
    } else {
        Write-Host "[WARN] D:\usbnet\ absent (RNDIS mode actif ?)" -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] D:\ non monté (normal si RNDIS actif)" -ForegroundColor Cyan
}

# Test réseau
Write-Host "`nTest connectivité réseau..." -ForegroundColor Yellow
Write-Host "Test ping Kindle (192.168.15.244)..." -ForegroundColor Yellow
if (Test-Connection -ComputerName 192.168.15.244 -Count 2 -Quiet) {
    Write-Host "[OK] Kindle joignable sur 192.168.15.244`n" -ForegroundColor Green
    
    # Test SSH
    Write-Host "Test port SSH..." -ForegroundColor Yellow
    $sshTest = Test-NetConnection -ComputerName 192.168.15.244 -Port 22 -WarningAction SilentlyContinue
    if ($sshTest.TcpTestSucceeded) {
        Write-Host "[OK] SSH disponible (port 22 ouvert)`n" -ForegroundColor Green
        Write-Host "Connexion SSH : ssh root@192.168.15.244`n" -ForegroundColor Cyan
    } else {
        Write-Host "[KO] SSH non accessible`n" -ForegroundColor Red
    }
} else {
    Write-Host "[KO] Kindle non joignable - USBNetwork activé sur Kindle ?`n" -ForegroundColor Red
}
