#!/bin/bash
#
# Script per la generazione e il rinnovo dei certificati SSL
#
# Gestisce:
# - Tailscale: aragorn.alpaca-scala.ts.net
# - Let's Encrypt: *.mbianchi.me (wildcard via Cloudflare DNS)
#
# Utilizzo: ./renew-certs.sh [--force] [--tailscale-only] [--letsencrypt-only]
#

set -euo pipefail

# ============================================
# CONFIGURAZIONE
# ============================================

# Tailscale
TAILSCALE_DOMAIN="aragorn.alpaca-scala.ts.net"

# Let's Encrypt / Cloudflare
LETSENCRYPT_DOMAIN="mbianchi.me"
LETSENCRYPT_WILDCARD="*.mbianchi.me"
CLOUDFLARE_CREDENTIALS="/etc/letsencrypt/cloudflare.ini"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@mbianchi.me}"

# Directory
NGINX_SSL_DIR="/mnt/secondary/containers/nginx/ssl"
LOG_FILE="/var/log/cert-renewal.log"

# Rinnova se scade entro N giorni
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
log_warn() { log "WARN" "$@"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root"
        exit 1
    fi
}

create_directories() {
    if [[ ! -d "$NGINX_SSL_DIR" ]]; then
        log_info "Creazione directory SSL: $NGINX_SSL_DIR"
        mkdir -p "$NGINX_SSL_DIR"
        chmod 755 "$NGINX_SSL_DIR"
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
# TAILSCALE
# ============================================

check_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        log_warn "Tailscale non è installato, skip certificato Tailscale"
        return 1
    fi
    
    if ! tailscale status &> /dev/null; then
        log_warn "Tailscale non è connesso, skip certificato Tailscale"
        return 1
    fi
    
    return 0
}

generate_tailscale_cert() {
    local domain="$1"
    
    log_info "Generazione certificato Tailscale per $domain..."
    
    if ! tailscale cert \
        --cert-file="$NGINX_SSL_DIR/$domain.crt" \
        --key-file="$NGINX_SSL_DIR/$domain.key" \
        "$domain" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Errore nella generazione del certificato Tailscale"
        return 1
    fi
    
    if [[ ! -f "$NGINX_SSL_DIR/$domain.crt" ]] || [[ ! -f "$NGINX_SSL_DIR/$domain.key" ]]; then
        log_error "File certificato Tailscale non trovati"
        return 1
    fi
    
    chmod 644 "$NGINX_SSL_DIR/$domain.crt"
    chmod 600 "$NGINX_SSL_DIR/$domain.key"
    
    log_success "Certificato Tailscale generato con successo"
    return 0
}

renew_tailscale() {
    local force="$1"
    
    log_info "------------------------------------------"
    log_info "Rinnovo certificato Tailscale"
    log_info "Dominio: $TAILSCALE_DOMAIN"
    log_info "------------------------------------------"
    
    if ! check_tailscale; then
        return 1
    fi
    
    local cert_file="$NGINX_SSL_DIR/$TAILSCALE_DOMAIN.crt"
    local needs_renewal=false
    
    if [[ "$force" == true ]]; then
        log_info "Rinnovo forzato"
        needs_renewal=true
    elif ! check_certificate_expiry "$cert_file" "$RENEWAL_DAYS"; then
        needs_renewal=true
    else
        log_info "Certificato ancora valido"
    fi
    
    if [[ "$needs_renewal" == true ]]; then
        generate_tailscale_cert "$TAILSCALE_DOMAIN"
    fi
}

# ============================================
# LET'S ENCRYPT / CLOUDFLARE
# ============================================

check_certbot() {
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot non è installato"
        log_info "Installa con: apt install certbot python3-certbot-dns-cloudflare"
        return 1
    fi
    return 0
}

check_cloudflare_credentials() {
    if [[ ! -f "$CLOUDFLARE_CREDENTIALS" ]]; then
        log_error "File credenziali Cloudflare non trovato: $CLOUDFLARE_CREDENTIALS"
        log_info "Crea il file con:"
        log_info "  echo 'dns_cloudflare_api_token = YOUR_API_TOKEN' > $CLOUDFLARE_CREDENTIALS"
        log_info "  chmod 600 $CLOUDFLARE_CREDENTIALS"
        return 1
    fi
    return 0
}

generate_letsencrypt_cert() {
    local domain="$1"
    local wildcard="$2"
    
    log_info "Generazione certificato Let's Encrypt per $domain e $wildcard..."
    
    # Genera/rinnova certificato con Certbot e Cloudflare DNS
    if ! certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CLOUDFLARE_CREDENTIALS" \
        --dns-cloudflare-propagation-seconds 30 \
        -d "$domain" \
        -d "$wildcard" \
        --email "$LETSENCRYPT_EMAIL" \
        --agree-tos \
        --non-interactive \
        --keep-until-expiring \
        2>&1 | tee -a "$LOG_FILE"; then
        log_error "Errore nella generazione del certificato Let's Encrypt"
        return 1
    fi
    
    # Copia certificati nella directory nginx
    local le_dir="/etc/letsencrypt/live/$domain"
    
    if [[ -d "$le_dir" ]]; then
        log_info "Copia certificati in $NGINX_SSL_DIR..."
        cp "$le_dir/fullchain.pem" "$NGINX_SSL_DIR/$domain.crt"
        cp "$le_dir/privkey.pem" "$NGINX_SSL_DIR/$domain.key"
        chmod 644 "$NGINX_SSL_DIR/$domain.crt"
        chmod 600 "$NGINX_SSL_DIR/$domain.key"
        log_success "Certificato Let's Encrypt copiato con successo"
    else
        log_error "Directory Let's Encrypt non trovata: $le_dir"
        return 1
    fi
    
    return 0
}

renew_letsencrypt() {
    local force="$1"
    
    log_info "------------------------------------------"
    log_info "Rinnovo certificato Let's Encrypt"
    log_info "Domini: $LETSENCRYPT_DOMAIN, $LETSENCRYPT_WILDCARD"
    log_info "------------------------------------------"
    
    if ! check_certbot; then
        return 1
    fi
    
    if ! check_cloudflare_credentials; then
        return 1
    fi
    
    local cert_file="$NGINX_SSL_DIR/$LETSENCRYPT_DOMAIN.crt"
    local needs_renewal=false
    
    if [[ "$force" == true ]]; then
        log_info "Rinnovo forzato"
        needs_renewal=true
    elif ! check_certificate_expiry "$cert_file" "$RENEWAL_DAYS"; then
        needs_renewal=true
    else
        log_info "Certificato ancora valido"
    fi
    
    if [[ "$needs_renewal" == true ]]; then
        generate_letsencrypt_cert "$LETSENCRYPT_DOMAIN" "$LETSENCRYPT_WILDCARD"
    fi
}

# ============================================
# MAIN
# ============================================

show_help() {
    echo "Utilizzo: $0 [opzioni]"
    echo ""
    echo "Rinnova i certificati SSL per:"
    echo "  - Tailscale: $TAILSCALE_DOMAIN"
    echo "  - Let's Encrypt: $LETSENCRYPT_DOMAIN, $LETSENCRYPT_WILDCARD"
    echo ""
    echo "Opzioni:"
    echo "  --force              Forza il rinnovo di tutti i certificati"
    echo "  --tailscale-only     Rinnova solo il certificato Tailscale"
    echo "  --letsencrypt-only   Rinnova solo il certificato Let's Encrypt"
    echo "  -h, --help           Mostra questo messaggio"
    echo ""
    echo "Variabili d'ambiente:"
    echo "  LETSENCRYPT_EMAIL    Email per Let's Encrypt (default: admin@mbianchi.me)"
}

main() {
    local force_renewal=false
    local tailscale_only=false
    local letsencrypt_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_renewal=true
                shift
                ;;
            --tailscale-only)
                tailscale_only=true
                shift
                ;;
            --letsencrypt-only)
                letsencrypt_only=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Opzione sconosciuta: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "Avvio rinnovo certificati SSL"
    log_info "=========================================="
    
    check_root
    create_directories
    
    local nginx_reload_needed=false
    
    # Rinnovo Tailscale
    if [[ "$letsencrypt_only" == false ]]; then
        if renew_tailscale "$force_renewal"; then
            nginx_reload_needed=true
        fi
    fi
    
    # Rinnovo Let's Encrypt
    if [[ "$tailscale_only" == false ]]; then
        if renew_letsencrypt "$force_renewal"; then
            nginx_reload_needed=true
        fi
    fi
    
    # Reload nginx se necessario
    if [[ "$nginx_reload_needed" == true ]]; then
        reload_nginx
    fi
    
    log_info "=========================================="
    log_info "Fine processo"
    log_info "=========================================="
}

main "$@"

