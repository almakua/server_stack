#!/bin/bash
#
# Script di installazione dei servizi systemd per il rinnovo certificati Tailscale
#
# Utilizzo: sudo ./install-systemd.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/aragorn"

echo "=========================================="
echo "Installazione Tailscale Cert Renewal"
echo "Dominio: aragorn.alpaca-scala.ts.net"
echo "=========================================="

# Verifica root
if [[ $EUID -ne 0 ]]; then
    echo "Errore: Questo script deve essere eseguito come root"
    exit 1
fi

# Crea directory di installazione
echo "[1/6] Creazione directory di installazione..."
mkdir -p "$INSTALL_DIR/scripts"

# Copia script principale
echo "[2/6] Copia script di rinnovo..."
cp "$SCRIPT_DIR/renew-tailscale-certs.sh" "$INSTALL_DIR/scripts/"
chmod +x "$INSTALL_DIR/scripts/renew-tailscale-certs.sh"

# Copia file systemd
echo "[3/6] Installazione unit systemd..."
cp "$SCRIPT_DIR/systemd/tailscale-cert-renewal.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/tailscale-cert-renewal.timer" /etc/systemd/system/

# Reload systemd
echo "[4/6] Reload systemd daemon..."
systemctl daemon-reload

# Abilita e avvia il timer
echo "[5/6] Abilitazione timer..."
systemctl enable tailscale-cert-renewal.timer
systemctl start tailscale-cert-renewal.timer

# Crea directory SSL se non esiste
echo "[6/6] Creazione directory SSL..."
mkdir -p /mnt/secondary/containers/nginx/ssl

echo ""
echo "=========================================="
echo "Installazione completata!"
echo "=========================================="
echo ""
echo "Comandi utili:"
echo ""
echo "  # Genera certificato subito"
echo "  sudo $INSTALL_DIR/scripts/renew-tailscale-certs.sh --force"
echo ""
echo "  # Verifica stato del timer"
echo "  systemctl status tailscale-cert-renewal.timer"
echo ""
echo "  # Visualizza prossima esecuzione"
echo "  systemctl list-timers tailscale-cert-renewal.timer"
echo ""
echo "  # Esegui manualmente il servizio"
echo "  sudo systemctl start tailscale-cert-renewal.service"
echo ""
echo "  # Visualizza log"
echo "  journalctl -u tailscale-cert-renewal.service"
echo ""

