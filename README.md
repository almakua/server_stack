# 🎬 Aragorn Media Server Stack

Stack completo per la gestione automatizzata di media (film, serie TV, musica) con Docker Compose.

> 📖 **Prima installazione?** Segui la [Guida Setup Completa](SETUP.md) per configurare tutto passo-passo.

---

## 📋 Panoramica Servizi

| Servizio | Porta | URL | Descrizione |
|----------|-------|-----|-------------|
| **qBittorrent** | `8080` | `qbittorrent.mbianchi.me` | Client BitTorrent con WebUI |
| **Prowlarr** | `9696` | `prowlarr.mbianchi.me` | Gestione centralizzata degli indexer |
| **Sonarr** | `8989` | `sonarr.mbianchi.me` | Gestione automatica serie TV |
| **Radarr** | `7878` | `radarr.mbianchi.me` | Gestione automatica film |
| **Lidarr** | `8686` | `lidarr.mbianchi.me` | Gestione automatica musica |
| **Bazarr** | `6767` | `bazarr.mbianchi.me` | Download automatico sottotitoli |
| **Jellyfin** | `8096` | `jellyfin.mbianchi.me` | Media server per lo streaming |
| **Nginx** | `80/443` | - | Reverse proxy |
| **Watchtower** | - | - | Aggiornamento automatico container |

---

## 📁 Struttura Cartelle

### Volumi Media
```
/mnt/main/
├── downloads/      # Download qBittorrent
├── movies/         # Film (Radarr → Jellyfin)
├── series/         # Serie TV (Sonarr → Jellyfin)
└── music/          # Musica (Lidarr → Jellyfin)
```

### Configurazioni Container
```
/mnt/secondary/containers/
├── qbittorrent/
├── prowlarr/
├── sonarr/
├── radarr/
├── lidarr/
├── bazarr/
├── jellyfin/
└── nginx/
    ├── ssl/          # Certificati SSL (opzionale)
    └── logs/         # Log di accesso ed errori
```

### Configurazione Nginx (locale)
```
./nginx/
├── nginx.conf              # Configurazione principale
└── conf.d/
    ├── qbittorrent.conf    # *.mbianchi.me
    ├── prowlarr.conf
    ├── sonarr.conf
    ├── radarr.conf
    ├── lidarr.conf
    ├── bazarr.conf
    └── jellyfin.conf
```

### Script
```
./scripts/
├── renew-certs.sh              # Rinnovo certificati (Tailscale + Let's Encrypt)
├── install-systemd.sh          # Installazione servizi systemd
├── cloudflare.ini.example      # Template credenziali Cloudflare
└── systemd/
    ├── cert-renewal.service
    └── cert-renewal.timer
```

---

## 🚀 Installazione

### Prerequisiti

- Docker Engine 20.10+
- Docker Compose v2+
- Cartelle media già montate in `/mnt/main/`
- DNS configurato per `*.mbianchi.me` che punti al server
- **(Per transcodifica GPU)** NVIDIA Driver + NVIDIA Container Toolkit

### Verifica UID/GID

Prima di avviare, verifica il tuo UID e GID:

```bash
id -u  # Dovrebbe restituire 1000
id -g  # Dovrebbe restituire 1000
```

Se diversi, modifica `PUID` e `PGID` nel `docker-compose.yml`.

### Avvio

```bash
# Clona o entra nella cartella del progetto
cd aragorn

# Avvia tutti i servizi in background
docker compose up -d

# Verifica che tutti i container siano running
docker compose ps
```

---

## 🔧 Configurazione Iniziale

### 1️⃣ qBittorrent

1. Accedi a `http://localhost:8080`
2. **Credenziali iniziali**: `admin` / password nei log
   ```bash
   docker logs qbittorrent 2>&1 | grep -i password
   ```
3. Vai in **Impostazioni → WebUI** e cambia la password
4. Vai in **Impostazioni → Download**:
   - Default Save Path: `/downloads`
5. Vai in **Impostazioni → BitTorrent**:
   - Abilita "Quando il rapporto raggiunge..." per il seeding

### 2️⃣ Prowlarr

1. Accedi a `http://localhost:9696`
2. Crea un account admin
3. Vai in **Indexers → Add Indexer** e aggiungi i tuoi indexer/tracker
4. Vai in **Settings → Apps** e aggiungi:
   - Sonarr (host: `sonarr`, porta: `8989`)
   - Radarr (host: `radarr`, porta: `7878`)
   - Lidarr (host: `lidarr`, porta: `8686`)
   
   > Le API Key si trovano in ogni app sotto Settings → General

### 3️⃣ Sonarr (Serie TV)

1. Accedi a `http://localhost:8989`
2. Completa il wizard iniziale
3. **Settings → Media Management**:
   - Root Folder: `/tv`
   - Abilita "Rename Episodes"
4. **Settings → Download Clients → Add**:
   - Tipo: qBittorrent
   - Host: `qbittorrent`
   - Port: `8080`
   - Username/Password: le tue credenziali qBittorrent
5. **Settings → General**: copia la API Key per Prowlarr e Bazarr

### 4️⃣ Radarr (Film)

1. Accedi a `http://localhost:7878`
2. Completa il wizard iniziale
3. **Settings → Media Management**:
   - Root Folder: `/movies`
   - Abilita "Rename Movies"
4. **Settings → Download Clients → Add**:
   - Tipo: qBittorrent
   - Host: `qbittorrent`
   - Port: `8080`
5. **Settings → General**: copia la API Key per Prowlarr e Bazarr

### 5️⃣ Lidarr (Musica)

1. Accedi a `http://localhost:8686`
2. Completa il wizard iniziale
3. **Settings → Media Management**:
   - Root Folder: `/music`
4. **Settings → Download Clients → Add**:
   - Tipo: qBittorrent
   - Host: `qbittorrent`
   - Port: `8080`
5. **Settings → General**: copia la API Key per Prowlarr

### 6️⃣ Bazarr (Sottotitoli)

1. Accedi a `http://localhost:6767`
2. **Settings → Sonarr**:
   - Address: `sonarr`
   - Port: `8989`
   - API Key: (da Sonarr)
   - Abilita
3. **Settings → Radarr**:
   - Address: `radarr`
   - Port: `7878`
   - API Key: (da Radarr)
   - Abilita
4. **Settings → Providers**: aggiungi provider sottotitoli (es. OpenSubtitles, Addic7ed)
5. **Settings → Languages**: configura le lingue desiderate (es. Italian, English)

### 7️⃣ Jellyfin (Media Server)

1. Accedi a `http://localhost:8096`
2. Completa il wizard iniziale
3. Aggiungi le librerie:
   - **Film**: `/data/movies`
   - **Serie TV**: `/data/tvshows`
   - **Musica**: `/data/music`
4. Configura utenti e accessi
5. (Opzionale) Installa plugin per metadati italiani

---

## 🔗 Rete Interna Docker

I container comunicano tra loro usando i nomi dei servizi:

| Da | A | Hostname |
|----|---|----------|
| Sonarr/Radarr/Lidarr | qBittorrent | `qbittorrent:8080` |
| Prowlarr | Sonarr | `sonarr:8989` |
| Prowlarr | Radarr | `radarr:7878` |
| Prowlarr | Lidarr | `lidarr:8686` |
| Bazarr | Sonarr | `sonarr:8989` |
| Bazarr | Radarr | `radarr:7878` |

---

## 🛠️ Comandi Utili

```bash
# Avvia tutti i servizi
docker compose up -d

# Ferma tutti i servizi
docker compose down

# Riavvia un servizio specifico
docker compose restart sonarr

# Visualizza log in tempo reale
docker compose logs -f

# Log di un servizio specifico
docker compose logs -f radarr

# Aggiorna manualmente le immagini
docker compose pull
docker compose up -d

# Stato dei container
docker compose ps

# Entra in un container
docker compose exec sonarr bash
```

---

## 🔄 Watchtower - Aggiornamenti Automatici

Watchtower controlla e aggiorna automaticamente tutti i container:

- **Orario**: Ogni giorno alle 04:00
- **Cleanup**: Rimuove automaticamente le immagini vecchie

Per modificare l'orario, cambia `WATCHTOWER_SCHEDULE` nel docker-compose.yml.

Formato cron: `secondi minuti ore giorno mese giorno_settimana`

```yaml
# Esempi:
- WATCHTOWER_SCHEDULE=0 0 4 * * *     # Ogni giorno alle 04:00
- WATCHTOWER_SCHEDULE=0 0 4 * * 0     # Ogni domenica alle 04:00
- WATCHTOWER_SCHEDULE=0 0 */6 * * *   # Ogni 6 ore
```

---

## 📊 Porte Riepilogo

| Porta | Servizio | Protocollo |
|-------|----------|------------|
| 80 | Nginx HTTP | TCP |
| 443 | Nginx HTTPS | TCP |
| 8080 | qBittorrent WebUI | TCP |
| 6881 | qBittorrent P2P | TCP/UDP |
| 9696 | Prowlarr | TCP |
| 8989 | Sonarr | TCP |
| 7878 | Radarr | TCP |
| 8686 | Lidarr | TCP |
| 6767 | Bazarr | TCP |
| 8096 | Jellyfin HTTP | TCP |
| 8920 | Jellyfin HTTPS | TCP |
| 7359 | Jellyfin Discovery | UDP |
| 1900 | Jellyfin DLNA | UDP |

---

## 🌐 Reverse Proxy (Nginx)

### URL Servizi

| Servizio | URL |
|----------|-----|
| qBittorrent | `http://qbittorrent.mbianchi.me` |
| Prowlarr | `http://prowlarr.mbianchi.me` |
| Sonarr | `http://sonarr.mbianchi.me` |
| Radarr | `http://radarr.mbianchi.me` |
| Lidarr | `http://lidarr.mbianchi.me` |
| Bazarr | `http://bazarr.mbianchi.me` |
| Jellyfin | `http://jellyfin.mbianchi.me` |

### Configurazione DNS

Configura i record DNS per puntare tutti i sottodomini al tuo server:

```
# Record A (esempio)
qbittorrent.mbianchi.me  →  IP_DEL_SERVER
prowlarr.mbianchi.me     →  IP_DEL_SERVER
sonarr.mbianchi.me       →  IP_DEL_SERVER
radarr.mbianchi.me       →  IP_DEL_SERVER
lidarr.mbianchi.me       →  IP_DEL_SERVER
bazarr.mbianchi.me       →  IP_DEL_SERVER
jellyfin.mbianchi.me     →  IP_DEL_SERVER

# Oppure un singolo record wildcard
*.mbianchi.me            →  IP_DEL_SERVER
```

### Abilitare HTTPS con Let's Encrypt

Per abilitare HTTPS, puoi usare Certbot:

```bash
# Installa certbot
sudo apt install certbot

# Genera certificati per tutti i domini
sudo certbot certonly --standalone \
  -d qbittorrent.mbianchi.me \
  -d prowlarr.mbianchi.me \
  -d sonarr.mbianchi.me \
  -d radarr.mbianchi.me \
  -d lidarr.mbianchi.me \
  -d bazarr.mbianchi.me \
  -d jellyfin.mbianchi.me

# Copia i certificati nella cartella nginx
sudo cp /etc/letsencrypt/live/qbittorrent.mbianchi.me/fullchain.pem /mnt/secondary/containers/nginx/ssl/
sudo cp /etc/letsencrypt/live/qbittorrent.mbianchi.me/privkey.pem /mnt/secondary/containers/nginx/ssl/
```

Poi modifica i file in `nginx/conf.d/` per usare HTTPS:

```nginx
server {
    listen 80;
    server_name esempio.mbianchi.me;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name esempio.mbianchi.me;
    
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    # ... resto della configurazione
}
```

### Test configurazione Nginx

```bash
# Verifica sintassi configurazione
docker compose exec nginx nginx -t

# Ricarica configurazione senza downtime
docker compose exec nginx nginx -s reload
```

---

## 🔐 Certificati SSL (HTTPS)

Lo stack gestisce automaticamente due tipi di certificati:

| Tipo | Dominio | Provider |
|------|---------|----------|
| Tailscale | `aragorn.alpaca-scala.ts.net` | Tailscale |
| Wildcard | `*.mbianchi.me` | Let's Encrypt (Cloudflare DNS) |

### Prerequisiti

```bash
# Certbot con plugin Cloudflare (installato automaticamente dallo script)
sudo apt install certbot python3-certbot-dns-cloudflare
```

### Configurazione Cloudflare

1. Vai su [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Crea un **API Token** con permessi:
   - `Zone:DNS:Edit` per la zona `mbianchi.me`
3. Configura le credenziali:

```bash
# Copia il template
sudo cp /etc/letsencrypt/cloudflare.ini.example /etc/letsencrypt/cloudflare.ini

# Modifica con il tuo token
sudo vim /etc/letsencrypt/cloudflare.ini
# Inserisci: dns_cloudflare_api_token = IL_TUO_TOKEN

# Imposta permessi restrittivi
sudo chmod 600 /etc/letsencrypt/cloudflare.ini
```

### Installazione Rinnovo Automatico

```bash
# Rendi eseguibili gli script
chmod +x scripts/*.sh

# Installa i servizi systemd
sudo ./scripts/install-systemd.sh

# Genera i certificati iniziali
sudo /opt/aragorn/scripts/renew-certs.sh --force
```

### Comandi Utili

```bash
# Verifica stato del timer
systemctl status cert-renewal.timer

# Visualizza prossime esecuzioni
systemctl list-timers cert-renewal.timer

# Rinnova tutti i certificati
sudo systemctl start cert-renewal.service

# Forza rinnovo
sudo /opt/aragorn/scripts/renew-certs.sh --force

# Solo Tailscale
sudo /opt/aragorn/scripts/renew-certs.sh --tailscale-only --force

# Solo Let's Encrypt
sudo /opt/aragorn/scripts/renew-certs.sh --letsencrypt-only --force

# Visualizza log
journalctl -u cert-renewal.service
cat /var/log/cert-renewal.log
```

### File Certificati

I certificati vengono salvati in:
```
/mnt/secondary/containers/nginx/ssl/
├── aragorn.alpaca-scala.ts.net.crt   # Tailscale
├── aragorn.alpaca-scala.ts.net.key
├── mbianchi.me.crt                    # Let's Encrypt wildcard
└── mbianchi.me.key
```

Il timer esegue il rinnovo il **1° e 15° di ogni mese alle 03:00**.

---

## 🔒 Sicurezza

### Architettura di rete

```
Internet → [Nginx :80/:443] → [Rete Docker isolata] → Servizi
                                    ↑
                              mediastack (172.20.0.0/16)
```

- **I servizi NON sono esposti direttamente** - accessibili solo via nginx
- **Rete Docker dedicata** - i container comunicano solo tra loro
- **Porte esposte minime**:
  - `80/443` - Nginx (reverse proxy)
  - `6881` - qBittorrent P2P (necessario per torrent)
  - `7359/1900` - Jellyfin discovery/DLNA (opzionale, per app locali)

### Protezioni Nginx

| Protezione | Descrizione |
|------------|-------------|
| **Rate Limiting** | 30 req/s generale, 5 req/s per login |
| **Connessioni simultanee** | Max 50-100 per IP |
| **Security Headers** | X-Frame-Options, X-Content-Type-Options, XSS Protection |
| **Blocco bot malevoli** | sqlmap, nikto, nmap, masscan |
| **Server tokens nascosti** | Versione nginx non esposta |
| **TLS moderno** | Solo TLSv1.2/1.3, cipher suite sicure |

### Raccomandazioni aggiuntive

```bash
# 1. Firewall - blocca tutto tranne le porte necessarie
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 6881/tcp    # qBittorrent
sudo ufw allow 6881/udp
sudo ufw enable

# 2. Fail2ban per protezione brute force (opzionale)
sudo apt install fail2ban
```

### HTTPS per domini pubblici

Per `*.mbianchi.me` usa Let's Encrypt (vedi sezione dedicata nel README).

---

## 🐛 Troubleshooting

### Permessi file
Se hai problemi di permessi sulle cartelle media:
```bash
sudo chown -R 1000:1000 /mnt/main/downloads
sudo chown -R 1000:1000 /mnt/main/movies
sudo chown -R 1000:1000 /mnt/main/series
sudo chown -R 1000:1000 /mnt/main/music
```

### Container non si avvia
```bash
# Controlla i log
docker compose logs nome_servizio

# Ricostruisci il container
docker compose up -d --force-recreate nome_servizio
```

### qBittorrent: password dimenticata
```bash
# Ferma il container
docker compose stop qbittorrent

# Rimuovi il file di configurazione
rm /mnt/secondary/containers/qbittorrent/qBittorrent/qBittorrent.conf

# Riavvia - verrà generata nuova password
docker compose start qbittorrent
docker logs qbittorrent 2>&1 | grep -i password
```

### Jellyfin: accelerazione hardware NVIDIA

Il docker-compose è già configurato per NVIDIA GPU. Prerequisiti sul sistema host:

```bash
# 1. Installa driver NVIDIA
sudo apt install nvidia-driver-535  # o versione più recente

# 2. Installa NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt install -y nvidia-container-toolkit

# 3. Configura Docker per usare NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 4. Verifica che funzioni
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu18.04 nvidia-smi
```

In Jellyfin, vai in **Dashboard → Playback → Transcoding**:
- Hardware acceleration: **NVIDIA NVENC**
- Abilita: decoding e encoding per i codec supportati

### Jellyfin: accelerazione hardware Intel (alternativa)

Se hai una GPU Intel invece di NVIDIA, modifica il servizio jellyfin:
```yaml
jellyfin:
  # rimuovi runtime: nvidia e la sezione deploy
  devices:
    - /dev/dri:/dev/dri  # Intel QuickSync
```

### Spazio su disco
```bash
# Pulisci immagini Docker non utilizzate
docker system prune -a

# Verifica spazio usato da Docker
docker system df
```

---

## 📜 Licenza

Questo stack utilizza solo software open source:
- [qBittorrent](https://www.qbittorrent.org/) - GPL-2.0
- [Sonarr](https://sonarr.tv/) - GPL-3.0
- [Radarr](https://radarr.video/) - GPL-3.0
- [Lidarr](https://lidarr.audio/) - GPL-3.0
- [Bazarr](https://www.bazarr.media/) - GPL-3.0
- [Prowlarr](https://prowlarr.com/) - GPL-3.0
- [Jellyfin](https://jellyfin.org/) - GPL-2.0
- [Watchtower](https://containrrr.dev/watchtower/) - Apache-2.0
- [Nginx](https://nginx.org/) - BSD-2-Clause

---

<p align="center">
  <i>Happy streaming! 🍿</i>
</p>

