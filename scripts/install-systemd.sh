#!/bin/bash
#
# Script di installazione dei servizi systemd per il rinnovo certificati SSL
#
# Gestisce:
# - Tailscale: aragorn.alpaca-scala.ts.net
# - Let's Encrypt: *.mbianchi.me (via Cloudflare DNS)
#
# Utilizzo: sudo ./install-systemd.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/aragorn"

echo "=========================================="
echo "Installazione SSL Certificate Renewal"
echo "=========================================="
echo ""
echo "Certificati gestiti:"
echo "  - Tailscale: aragorn.alpaca-scala.ts.net"
echo "  - Let's Encrypt: *.mbianchi.me"
echo ""

# Verifica root
if [[ $EUID -ne 0 ]]; then
    echo "Errore: Questo script deve essere eseguito come root"
    exit 1
fi

# Installa dipendenze
echo "[1/8] Verifica dipendenze..."
if ! command -v certbot &> /dev/null; then
    echo "  Installazione Certbot..."
    apt update
    apt install -y certbot python3-certbot-dns-cloudflare
else
    echo "  Certbot già installato"
fi

# Crea directory
echo "[2/8] Creazione directory..."
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p /mnt/secondary/containers/nginx/ssl
mkdir -p /etc/letsencrypt

# Copia script principale
echo "[3/8] Copia script di rinnovo..."
cp "$SCRIPT_DIR/renew-certs.sh" "$INSTALL_DIR/scripts/"
chmod +x "$INSTALL_DIR/scripts/renew-certs.sh"

# Copia template credenziali Cloudflare
echo "[4/8] Copia template credenziali Cloudflare..."
if [[ ! -f /etc/letsencrypt/cloudflare.ini ]]; then
    cp "$SCRIPT_DIR/cloudflare.ini.example" /etc/letsencrypt/cloudflare.ini.example
    echo ""
    echo "  ⚠️  IMPORTANTE: Configura le credenziali Cloudflare!"
    echo "     sudo cp /etc/letsencrypt/cloudflare.ini.example /etc/letsencrypt/cloudflare.ini"
    echo "     sudo nano /etc/letsencrypt/cloudflare.ini"
    echo "     sudo chmod 600 /etc/letsencrypt/cloudflare.ini"
    echo ""
else
    echo "  Credenziali Cloudflare già presenti"
fi

# Copia file systemd
echo "[5/8] Installazione unit systemd..."
cp "$SCRIPT_DIR/systemd/cert-renewal.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/cert-renewal.timer" /etc/systemd/system/

# Rimuovi vecchi file se esistono
rm -f /etc/systemd/system/tailscale-cert-renewal.service
rm -f /etc/systemd/system/tailscale-cert-renewal.timer

# Reload systemd
echo "[6/8] Reload systemd daemon..."
systemctl daemon-reload

# Disabilita vecchio timer se esiste
systemctl disable tailscale-cert-renewal.timer 2>/dev/null || true
systemctl stop tailscale-cert-renewal.timer 2>/dev/null || true

# Abilita e avvia il timer
echo "[7/8] Abilitazione timer..."
systemctl enable cert-renewal.timer
systemctl start cert-renewal.timer

# Verifica stato
echo "[8/8] Verifica stato..."
echo ""

echo "=========================================="
echo "Installazione completata!"
echo "=========================================="
echo ""
echo "PROSSIMI PASSI:"
echo ""
echo "1. Configura le credenziali Cloudflare (se non già fatto):"
echo "   sudo cp /etc/letsencrypt/cloudflare.ini.example /etc/letsencrypt/cloudflare.ini"
echo "   sudo nano /etc/letsencrypt/cloudflare.ini"
echo "   sudo chmod 600 /etc/letsencrypt/cloudflare.ini"
echo ""
echo "2. Genera i certificati:"
echo "   sudo $INSTALL_DIR/scripts/renew-certs.sh --force"
echo ""
echo "COMANDI UTILI:"
echo ""
echo "  # Verifica stato del timer"
echo "  systemctl status cert-renewal.timer"
echo ""
echo "  # Visualizza prossime esecuzioni"
echo "  systemctl list-timers cert-renewal.timer"
echo ""
echo "  # Esegui manualmente"
echo "  sudo systemctl start cert-renewal.service"
echo ""
echo "  # Solo Tailscale"
echo "  sudo $INSTALL_DIR/scripts/renew-certs.sh --tailscale-only --force"
echo ""
echo "  # Solo Let's Encrypt"
echo "  sudo $INSTALL_DIR/scripts/renew-certs.sh --letsencrypt-only --force"
echo ""
echo "  # Visualizza log"
echo "  journalctl -u cert-renewal.service"
echo "  cat /var/log/cert-renewal.log"
echo ""
