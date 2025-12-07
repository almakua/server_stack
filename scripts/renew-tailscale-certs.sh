#!/bin/bash
#
# Script per la generazione e il rinnovo dei certificati Tailscale
# Esegue il rinnovo dei certificati e li copia nella cartella nginx
#
# Utilizzo: ./renew-tailscale-certs.sh [--force]
#
# Opzioni:
#   --force    Forza il rinnovo anche se i certificati non sono scaduti
#

set -euo pipefail

# ============================================
# CONFIGURAZIONE
# ============================================

# Nome del dominio Tailscale (modificare con il proprio)
TAILSCALE_DOMAIN="${TAILSCALE_DOMAIN:-casa.home}"

# Percorso della cartella SSL di nginx
NGINX_SSL_DIR="${NGINX_SSL_DIR:-/mnt/secondary/containers/nginx/ssl}"

# Percorso del docker-compose
COMPOSE_DIR="${COMPOSE_DIR:-/home/$(whoami)/aragorn}"

# File di log
LOG_FILE="${LOG_FILE:-/var/log/tailscale-cert-renewal.log}"

# Giorni prima della scadenza per il rinnovo
RENEWAL_DAYS="${RENEWAL_DAYS:-30}"

# ============================================
# FUNZIONI
# ============================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root"
        exit 1
    fi
}

check_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        log_error "Tailscale non è installato"
        exit 1
    fi
    
    if ! tailscale status &> /dev/null; then
        log_error "Tailscale non è connesso"
        exit 1
    fi
}

check_certificate_expiry() {
    local cert_file="$1"
    local days="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        return 1  # Certificato non esiste, necessario rinnovo
    fi
    
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$expiry_date" ]]; then
        return 1  # Impossibile leggere la data, necessario rinnovo
    fi
    
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_info "Certificato scade tra $days_until_expiry giorni"
    
    if [[ $days_until_expiry -le $days ]]; then
        return 1  # Certificato in scadenza
    fi
    
    return 0  # Certificato valido
}

create_directories() {
    if [[ ! -d "$NGINX_SSL_DIR" ]]; then
        log_info "Creazione directory SSL: $NGINX_SSL_DIR"
        mkdir -p "$NGINX_SSL_DIR"
        chmod 755 "$NGINX_SSL_DIR"
    fi
}

generate_tailscale_cert() {
    local domain="$1"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    log_info "Generazione certificato Tailscale per $domain..."
    
    # Genera il certificato tramite Tailscale
    if ! tailscale cert --cert-file="$temp_dir/$domain.crt" --key-file="$temp_dir/$domain.key" "$domain" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Errore nella generazione del certificato per $domain"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verifica che i file siano stati creati
    if [[ ! -f "$temp_dir/$domain.crt" ]] || [[ ! -f "$temp_dir/$domain.key" ]]; then
        log_error "File certificato non trovati dopo la generazione"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Copia i file nella directory SSL
    log_info "Copia certificati in $NGINX_SSL_DIR..."
    cp "$temp_dir/$domain.crt" "$NGINX_SSL_DIR/$domain.crt"
    cp "$temp_dir/$domain.key" "$NGINX_SSL_DIR/$domain.key"
    
    # Imposta i permessi corretti
    chmod 644 "$NGINX_SSL_DIR/$domain.crt"
    chmod 600 "$NGINX_SSL_DIR/$domain.key"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "Certificato generato con successo per $domain"
    return 0
}

reload_nginx() {
    log_info "Ricaricamento configurazione Nginx..."
    
    # Verifica se il container nginx è in esecuzione
    if docker ps --format '{{.Names}}' | grep -q '^nginx$'; then
        # Verifica la configurazione prima del reload
        if docker exec nginx nginx -t &>> "$LOG_FILE"; then
            docker exec nginx nginx -s reload &>> "$LOG_FILE"
            log_success "Nginx ricaricato con successo"
        else
            log_error "Errore nella configurazione Nginx, reload saltato"
            return 1
        fi
    else
        log_info "Container Nginx non in esecuzione, reload saltato"
    fi
}

send_notification() {
    local status="$1"
    local message="$2"
    
    # Placeholder per notifiche (es. email, Telegram, Discord)
    # Decommentare e configurare secondo necessità
    
    # Esempio: notifica via email
    # echo "$message" | mail -s "Tailscale Cert Renewal: $status" admin@example.com
    
    # Esempio: notifica via webhook
    # curl -X POST -H "Content-Type: application/json" \
    #     -d "{\"status\": \"$status\", \"message\": \"$message\"}" \
    #     https://your-webhook-url.com/notify
    
    :  # No-op se nessuna notifica configurata
}

# ============================================
# MAIN
# ============================================

main() {
    local force_renewal=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_renewal=true
                shift
                ;;
            --help|-h)
                echo "Utilizzo: $0 [--force]"
                echo ""
                echo "Opzioni:"
                echo "  --force    Forza il rinnovo anche se i certificati non sono scaduti"
                echo ""
                echo "Variabili d'ambiente:"
                echo "  TAILSCALE_DOMAIN   Dominio Tailscale (default: casa.home)"
                echo "  NGINX_SSL_DIR      Directory SSL nginx (default: /mnt/secondary/containers/nginx/ssl)"
                echo "  COMPOSE_DIR        Directory docker-compose (default: /home/\$USER/aragorn)"
                echo "  LOG_FILE           File di log (default: /var/log/tailscale-cert-renewal.log)"
                echo "  RENEWAL_DAYS       Giorni prima della scadenza per il rinnovo (default: 30)"
                exit 0
                ;;
            *)
                log_error "Opzione sconosciuta: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "Avvio rinnovo certificati Tailscale"
    log_info "=========================================="
    
    # Verifica prerequisiti
    check_root
    check_tailscale
    create_directories
    
    local cert_file="$NGINX_SSL_DIR/$TAILSCALE_DOMAIN.crt"
    local needs_renewal=false
    
    # Verifica se il certificato necessita rinnovo
    if [[ "$force_renewal" == true ]]; then
        log_info "Rinnovo forzato richiesto"
        needs_renewal=true
    elif ! check_certificate_expiry "$cert_file" "$RENEWAL_DAYS"; then
        log_info "Certificato necessita rinnovo"
        needs_renewal=true
    else
        log_info "Certificato ancora valido, rinnovo non necessario"
    fi
    
    if [[ "$needs_renewal" == true ]]; then
        if generate_tailscale_cert "$TAILSCALE_DOMAIN"; then
            reload_nginx
            send_notification "SUCCESS" "Certificato Tailscale rinnovato con successo per $TAILSCALE_DOMAIN"
            log_success "Processo completato con successo"
        else
            send_notification "FAILURE" "Errore nel rinnovo del certificato Tailscale per $TAILSCALE_DOMAIN"
            log_error "Processo terminato con errori"
            exit 1
        fi
    fi
    
    log_info "=========================================="
    log_info "Fine processo"
    log_info "=========================================="
}

main "$@"

