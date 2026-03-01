# Script de vérification USBNetwork installé
# À exécuter après installation sur Kindle

Write-Host "Vérification installation USBNetwork...
" -ForegroundColor Yellow

# Vérifier Kindle
if (!(Test-Path D:\)) {
    Write-Host "[KO] Kindle non détecté
" -ForegroundColor Red
    exit 1
}

# Vérifier dossier usbnet
if (Test-Path D:\usbnet) {
    Write-Host "[OK] D:\usbnet\ trouvé" -ForegroundColor Green
    Write-Host "Contenu :"
    Get-ChildItem D:\usbnet
} else {
    Write-Host "[KO] D:\usbnet\ absent - Installation échouée ?
" -ForegroundColor Red
    exit 1
}

# Test réseau
Write-Host "
Test connectivité réseau..." -ForegroundColor Yellow
Write-Host "Interface USB/RNDIS :"
Get-NetAdapter | Where-Object {$_.InterfaceDescription -match "RNDIS|USB" -and $_.Status -eq "Up"} | Format-Table -AutoSize

Write-Host "Test ping Kindle..." -ForegroundColor Yellow
if (Test-Connection -ComputerName 192.168.15.244 -Count 2 -Quiet) {
    Write-Host "[OK] Kindle joignable sur 192.168.15.244
" -ForegroundColor Green
    
    # Test SSH
    Write-Host "Test port SSH..." -ForegroundColor Yellow
    $sshTest = Test-NetConnection -ComputerName 192.168.15.244 -Port 22 -WarningAction SilentlyContinue
    if ($sshTest.TcpTestSucceeded) {
        Write-Host "[OK] SSH disponible (port 22 ouvert)
" -ForegroundColor Green
        Write-Host "Connexion SSH : ssh root@192.168.15.244
" -ForegroundColor Cyan
    } else {
        Write-Host "[KO] SSH non accessible
" -ForegroundColor Red
    }
} else {
    Write-Host "[KO] Kindle non joignable - USBNetwork activé ?
" -ForegroundColor Red
}
