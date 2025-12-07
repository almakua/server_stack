#!/bin/bash
#
# Configura qBittorrent per funzionare dietro reverse proxy
#

set -euo pipefail

QBIT_CONFIG="/mnt/secondary/containers/qbittorrent/qBittorrent/qBittorrent.conf"

echo "=========================================="
echo "Configurazione qBittorrent per Reverse Proxy"
echo "=========================================="

# Verifica root
if [[ $EUID -ne 0 ]]; then
    echo "Errore: Questo script deve essere eseguito come root"
    exit 1
fi

# Verifica che il file esista
if [[ ! -f "$QBIT_CONFIG" ]]; then
    echo "Errore: File di configurazione non trovato: $QBIT_CONFIG"
    echo "Assicurati che qBittorrent sia stato avviato almeno una volta."
    exit 1
fi

# Ferma qBittorrent
echo "[1/4] Fermando qBittorrent..."
cd /opt/aragorn 2>/dev/null || cd ~/aragorn
docker compose stop qbittorrent

# Backup config
echo "[2/4] Backup configurazione..."
cp "$QBIT_CONFIG" "$QBIT_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Modifica configurazione
echo "[3/4] Applicando configurazione reverse proxy..."

# Funzione per aggiungere/modificare una configurazione
set_config() {
    local key="$1"
    local value="$2"
    local file="$QBIT_CONFIG"
    
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        # Aggiungi sotto [Preferences] se esiste, altrimenti alla fine
        if grep -q "^\[Preferences\]" "$file"; then
            sed -i "/^\[Preferences\]/a ${key}=${value}" "$file"
        else
            echo "[Preferences]" >> "$file"
            echo "${key}=${value}" >> "$file"
        fi
    fi
}

# Applica le configurazioni per reverse proxy
set_config "WebUI\\\\CSRFProtection" "false"
set_config "WebUI\\\\HostHeaderValidation" "false"
set_config "WebUI\\\\TrustedReverseProxiesList" "172.20.0.0/16"
set_config "WebUI\\\\LocalHostAuth" "false"
set_config "WebUI\\\\AuthSubnetWhitelist" "172.20.0.0/16"
set_config "WebUI\\\\AuthSubnetWhitelistEnabled" "true"

echo "   Configurazioni applicate:"
echo "   - CSRF Protection: disabilitata"
echo "   - Host Header Validation: disabilitata"
echo "   - Trusted Proxies: 172.20.0.0/16"
echo "   - Subnet Whitelist: 172.20.0.0/16"

# Riavvia qBittorrent
echo "[4/4] Riavviando qBittorrent..."
docker compose start qbittorrent

# Attendi avvio
sleep 5

# Mostra password
echo ""
echo "=========================================="
echo "Configurazione completata!"
echo "=========================================="
echo ""
echo "Password temporanea:"
docker logs qbittorrent 2>&1 | grep -i "temporary password" | tail -1 || echo "(controlla i log se non appare)"
echo ""
echo "Accedi a: https://qbittorrent.mbianchi.me"
echo "Username: admin"
echo ""

