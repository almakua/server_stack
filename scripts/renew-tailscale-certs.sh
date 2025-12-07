#!/bin/bash
#
# Script per la generazione e il rinnovo dei certificati Tailscale
# per aragorn.alpaca-scala.ts.net
#
# Utilizzo: ./renew-tailscale-certs.sh [--force]
#

set -euo pipefail

# ============================================
# CONFIGURAZIONE
# ============================================

TAILSCALE_DOMAIN="aragorn.alpaca-scala.ts.net"
NGINX_SSL_DIR="/mnt/secondary/containers/nginx/ssl"
COMPOSE_DIR="/opt/aragorn"
LOG_FILE="/var/log/tailscale-cert-renewal.log"
RENEWAL_DAYS=30

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

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

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
        return 1
    fi
    
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$expiry_date" ]]; then
        return 1
    fi
    
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_info "Certificato scade tra $days_until_expiry giorni"
    
    if [[ $days_until_expiry -le $days ]]; then
        return 1
    fi
    
    return 0
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
    
    log_info "Generazione certificato Tailscale per $domain..."
    
    # Genera il certificato tramite Tailscale direttamente nella directory SSL
    if ! tailscale cert \
        --cert-file="$NGINX_SSL_DIR/$domain.crt" \
        --key-file="$NGINX_SSL_DIR/$domain.key" \
        "$domain" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Errore nella generazione del certificato per $domain"
        return 1
    fi
    
    # Verifica che i file siano stati creati
    if [[ ! -f "$NGINX_SSL_DIR/$domain.crt" ]] || [[ ! -f "$NGINX_SSL_DIR/$domain.key" ]]; then
        log_error "File certificato non trovati dopo la generazione"
        return 1
    fi
    
    # Imposta i permessi corretti
    chmod 644 "$NGINX_SSL_DIR/$domain.crt"
    chmod 600 "$NGINX_SSL_DIR/$domain.key"
    
    log_success "Certificato generato con successo per $domain"
    return 0
}

reload_nginx() {
    log_info "Ricaricamento configurazione Nginx..."
    
    if docker ps --format '{{.Names}}' | grep -q '^nginx$'; then
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

# ============================================
# MAIN
# ============================================

main() {
    local force_renewal=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_renewal=true
                shift
                ;;
            --help|-h)
                echo "Utilizzo: $0 [--force]"
                echo ""
                echo "Rinnova il certificato Tailscale per $TAILSCALE_DOMAIN"
                echo ""
                echo "Opzioni:"
                echo "  --force    Forza il rinnovo anche se il certificato non è scaduto"
                exit 0
                ;;
            *)
                log_error "Opzione sconosciuta: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "Avvio rinnovo certificato Tailscale"
    log_info "Dominio: $TAILSCALE_DOMAIN"
    log_info "=========================================="
    
    check_root
    check_tailscale
    create_directories
    
    local cert_file="$NGINX_SSL_DIR/$TAILSCALE_DOMAIN.crt"
    local needs_renewal=false
    
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
            log_success "Processo completato con successo"
        else
            log_error "Processo terminato con errori"
            exit 1
        fi
    fi
    
    log_info "=========================================="
    log_info "Fine processo"
    log_info "=========================================="
}

main "$@"

