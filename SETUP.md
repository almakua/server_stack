# 🛠️ Guida Setup Completa

Questa guida ti accompagna passo-passo nella configurazione completa del media server stack.

---

## 📑 Indice

1. [Fase 1: Preparazione Server](#-fase-1-preparazione-server)
2. [Fase 2: Preparazione Cartelle](#-fase-2-preparazione-cartelle)
3. [Fase 3: Firewall](#-fase-3-firewall)
4. [Fase 4: Certificato Tailscale](#-fase-4-certificato-tailscale)
5. [Fase 5: Avvio Stack](#-fase-5-avvio-stack)
6. [Fase 6: Configurazione Web](#-fase-6-configurazione-web-interfaces)
7. [Verifica Finale](#-verifica-finale)
8. [Checklist](#-checklist-finale)

---

## 💻 Fase 1: Preparazione Server

### Aggiornamento Sistema

```bash
sudo apt update && sudo apt upgrade -y
```

### Installazione Docker

```bash
# Installa Docker
curl -fsSL https://get.docker.com | sudo sh

# Aggiungi utente al gruppo docker
sudo usermod -aG docker $USER

# ⚠️ Esci e rientra nella sessione per applicare il gruppo
exit
```

### Installazione Docker Compose

```bash
sudo apt install docker-compose-plugin -y

# Verifica installazione
docker compose version
```

### Installazione Driver e Toolkit NVIDIA (Solo GPU NVIDIA)

<details>
<summary>📦 Ubuntu 22.04 / 24.04 - Clicca per espandere</summary>

#### Step 1: Installa driver NVIDIA

```bash
# Verifica che la GPU sia rilevata
lspci | grep -i nvidia

# Aggiungi repository driver
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt update

# Installa driver (automatico)
sudo ubuntu-drivers autoinstall

# OPPURE versione specifica
sudo apt install -y nvidia-driver-535

# Riavvia
sudo reboot
```

#### Step 2: Verifica driver

```bash
nvidia-smi
```

#### Step 3: Installa NVIDIA Container Toolkit

```bash
# Aggiungi repository NVIDIA
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Installa toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configura Docker per NVIDIA
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verifica funzionamento
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu18.04 nvidia-smi
```

</details>

<details>
<summary>📦 Debian 13 (Trixie) - Clicca per espandere</summary>

#### Step 1: Abilita repository non-free

```bash
# Verifica che la GPU sia rilevata
lspci | grep -i nvidia

# Modifica sources.list
sudo vim /etc/apt/sources.list
```

Assicurati che le righe contengano `non-free non-free-firmware`:

```
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
```

Salva ed esci (`:wq`)

#### Step 2: Installa driver NVIDIA

```bash
# Installa dipendenze
sudo apt update
sudo apt install -y linux-headers-$(uname -r) build-essential dkms

# Installa driver NVIDIA
sudo apt install -y nvidia-driver firmware-misc-nonfree

# Blacklist driver nouveau
echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf

# Rigenera initramfs
sudo update-initramfs -u

# Riavvia
sudo reboot
```

#### Step 3: Verifica driver

```bash
nvidia-smi
```

#### Step 4: Installa NVIDIA Container Toolkit

```bash
# Aggiungi repository NVIDIA
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Installa toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configura Docker per NVIDIA
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verifica funzionamento
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu18.04 nvidia-smi
```

</details>

---

## 📁 Fase 2: Preparazione Cartelle

### Cartelle Media

```bash
# Crea struttura cartelle media
sudo mkdir -p /mnt/main/{downloads,movies,series,music}

# Imposta permessi
sudo chown -R 1000:1000 /mnt/main
```

### Cartelle Configurazione

```bash
# Crea struttura cartelle config
sudo mkdir -p /mnt/secondary/containers/{qbittorrent,prowlarr,sonarr,radarr,lidarr,bazarr,jellyfin}
sudo mkdir -p /mnt/secondary/containers/nginx/{ssl,logs}

# Imposta permessi
sudo chown -R 1000:1000 /mnt/secondary/containers
```

### Clone Repository

```bash
cd ~
git clone git@github.com:almakua/server_stack.git aragorn
cd aragorn
```

---

## 🛡️ Fase 3: Firewall

```bash
# Configura regole firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Porte essenziali
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP (nginx)
sudo ufw allow 443/tcp     # HTTPS (nginx)
sudo ufw allow 6881/tcp    # qBittorrent P2P
sudo ufw allow 6881/udp    # qBittorrent P2P

# Attiva firewall
sudo ufw enable

# Verifica stato
sudo ufw status
```

---

## 🔐 Fase 4: Certificati SSL

Lo stack usa due certificati:
- **Tailscale**: `aragorn.alpaca-scala.ts.net`
- **Let's Encrypt**: `*.mbianchi.me` (wildcard via Cloudflare DNS)

### 4.1 Installazione Tailscale

```bash
# Installa Tailscale (se non già installato)
curl -fsSL https://tailscale.com/install.sh | sh

# Connetti alla rete Tailscale
sudo tailscale up
```

### 4.2 Configurazione Cloudflare API

1. Vai su [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Clicca **Create Token**
3. Usa template **Edit zone DNS** oppure crea custom con:
   - Permissions: `Zone > DNS > Edit`
   - Zone Resources: `Include > Specific zone > mbianchi.me`
4. Copia il token generato

```bash
# Crea file credenziali
sudo mkdir -p /etc/letsencrypt
sudo vim /etc/letsencrypt/cloudflare.ini
```

Inserisci:
```ini
dns_cloudflare_api_token = IL_TUO_TOKEN_QUI
```

```bash
# Imposta permessi sicuri
sudo chmod 600 /etc/letsencrypt/cloudflare.ini
```

### 4.3 Installazione Rinnovo Automatico

```bash
cd ~/aragorn

# Rendi eseguibili gli script
chmod +x scripts/*.sh

# Installa servizi systemd (installa anche certbot se mancante)
sudo ./scripts/install-systemd.sh

# Genera tutti i certificati
sudo /opt/aragorn/scripts/renew-certs.sh --force
```

> 💡 I certificati verranno rinnovati automaticamente il 1° e 15° di ogni mese

### 4.4 Verifica

```bash
# Controlla che i certificati siano stati generati
ls -la /mnt/secondary/containers/nginx/ssl/

# Output atteso:
# aragorn.alpaca-scala.ts.net.crt
# aragorn.alpaca-scala.ts.net.key
# mbianchi.me.crt
# mbianchi.me.key
```

---

## 🚀 Fase 5: Avvio Stack

### Avvio Container

```bash
cd ~/aragorn

# Avvia tutti i servizi
docker compose up -d

# Verifica stato
docker compose ps
```

**Output atteso:**
```
NAME          STATUS
qbittorrent   running
prowlarr      running
sonarr        running
radarr        running
lidarr        running
bazarr        running
jellyfin      running
watchtower    running
nginx         running
```

### Recupero Password qBittorrent

```bash
docker logs qbittorrent 2>&1 | grep -i password
```

> 📝 Salva questa password, ti servirà per il primo login

### Monitoraggio Log

```bash
# Tutti i log
docker compose logs -f

# Log singolo servizio
docker compose logs -f sonarr

# Premi Ctrl+C per uscire
```

---

## 🌐 Fase 6: Configurazione Web Interfaces

### Accesso ai Servizi

| Servizio | URL |
|----------|-----|
| qBittorrent | `https://qbittorrent.mbianchi.me` |
| Prowlarr | `https://prowlarr.mbianchi.me` |
| Sonarr | `https://sonarr.mbianchi.me` |
| Radarr | `https://radarr.mbianchi.me` |
| Lidarr | `https://lidarr.mbianchi.me` |
| Bazarr | `https://bazarr.mbianchi.me` |
| Jellyfin | `https://jellyfin.mbianchi.me` |

> HTTP viene automaticamente reindirizzato a HTTPS

---

### 1️⃣ qBittorrent

> 🔗 `https://qbittorrent.mbianchi.me`

**Prima di accedere**, configura qBittorrent per il reverse proxy:

```bash
sudo /opt/aragorn/scripts/configure-qbittorrent.sh
```

| # | Azione |
|---|--------|
| 1 | Accedi con **username:** `admin` **password:** (mostrata dallo script) |
| 2 | **Tools → Options → Web UI** |
|   | ↳ Cambia la password |
| 3 | **Tools → Options → Downloads** |
|   | ↳ Default Save Path: `/downloads` |
| 4 | **Tools → Options → BitTorrent** |
|   | ↳ Abilita "When ratio reaches" |
|   | ↳ Imposta ratio: `1.0` |

---

### 2️⃣ Prowlarr

> 🔗 `https://prowlarr.mbianchi.me`

| # | Azione |
|---|--------|
| 1 | **Primo accesso:** Crea utente admin |
| 2 | **Settings → General** |
|   | ↳ 📋 Copia **API Key** (servirà dopo) |
| 3 | **Indexers → Add Indexer** |
|   | ↳ Cerca e aggiungi i tuoi indexer preferiti |
|   | ↳ Configura credenziali per ciascuno |

---

### 3️⃣ Sonarr (Serie TV)

> 🔗 `https://sonarr.mbianchi.me`

| # | Azione |
|---|--------|
| 1 | Completa il wizard iniziale |
| 2 | **Settings → General** |
|   | ↳ 📋 Copia **API Key** |
| 3 | **Settings → Media Management** |
|   | ↳ Click **Add Root Folder** |
|   | ↳ Path: `/tv` |
| 4 | **Settings → Download Clients → ➕** |
|   | ↳ Seleziona **qBittorrent** |
|   | ↳ Host: `qbittorrent` |
|   | ↳ Port: `8080` |
|   | ↳ Username: `admin` |
|   | ↳ Password: (la nuova password) |
|   | ↳ **Test** → **Save** |
| 5 | **Torna in Prowlarr** |
|   | ↳ **Settings → Apps → ➕ → Sonarr** |
|   | ↳ Prowlarr Server: `http://prowlarr:9696` |
|   | ↳ Sonarr Server: `http://sonarr:8989` |
|   | ↳ API Key: (da Sonarr) |
|   | ↳ **Test** → **Save** |

---

### 4️⃣ Radarr (Film)

> 🔗 `https://radarr.mbianchi.me`

| # | Azione |
|---|--------|
| 1 | Completa il wizard iniziale |
| 2 | **Settings → General** |
|   | ↳ 📋 Copia **API Key** |
| 3 | **Settings → Media Management** |
|   | ↳ Click **Add Root Folder** |
|   | ↳ Path: `/movies` |
| 4 | **Settings → Download Clients → ➕** |
|   | ↳ Seleziona **qBittorrent** |
|   | ↳ Host: `qbittorrent` |
|   | ↳ Port: `8080` |
|   | ↳ Username: `admin` |
|   | ↳ Password: (la nuova password) |
|   | ↳ **Test** → **Save** |
| 5 | **Torna in Prowlarr** |
|   | ↳ **Settings → Apps → ➕ → Radarr** |
|   | ↳ Prowlarr Server: `http://prowlarr:9696` |
|   | ↳ Radarr Server: `http://radarr:7878` |
|   | ↳ API Key: (da Radarr) |
|   | ↳ **Test** → **Save** |

---

### 5️⃣ Lidarr (Musica)

> 🔗 `https://lidarr.mbianchi.me`

| # | Azione |
|---|--------|
| 1 | Completa il wizard iniziale |
| 2 | **Settings → General** |
|   | ↳ 📋 Copia **API Key** |
| 3 | **Settings → Media Management** |
|   | ↳ Click **Add Root Folder** |
|   | ↳ Path: `/music` |
| 4 | **Settings → Download Clients → ➕** |
|   | ↳ Seleziona **qBittorrent** |
|   | ↳ Host: `qbittorrent` |
|   | ↳ Port: `8080` |
|   | ↳ Username: `admin` |
|   | ↳ Password: (la nuova password) |
|   | ↳ **Test** → **Save** |
| 5 | **Torna in Prowlarr** |
|   | ↳ **Settings → Apps → ➕ → Lidarr** |
|   | ↳ Prowlarr Server: `http://prowlarr:9696` |
|   | ↳ Lidarr Server: `http://lidarr:8686` |
|   | ↳ API Key: (da Lidarr) |
|   | ↳ **Test** → **Save** |

---

### 6️⃣ Bazarr (Sottotitoli)

> 🔗 `https://bazarr.mbianchi.me`

| # | Azione |
|---|--------|
| 1 | **Settings → Sonarr** |
|   | ↳ ✅ Enabled |
|   | ↳ Address: `sonarr` |
|   | ↳ Port: `8989` |
|   | ↳ API Key: (da Sonarr) |
|   | ↳ **Test** → **Save** |
| 2 | **Settings → Radarr** |
|   | ↳ ✅ Enabled |
|   | ↳ Address: `radarr` |
|   | ↳ Port: `7878` |
|   | ↳ API Key: (da Radarr) |
|   | ↳ **Test** → **Save** |
| 3 | **Settings → Providers → ➕** |
|   | ↳ Aggiungi provider sottotitoli: |
|   | ↳ OpenSubtitles.com (richiede account gratuito) |
|   | ↳ Addic7ed |
|   | ↳ Subscene |
| 4 | **Settings → Languages** |
|   | ↳ Aggiungi: **Italian** |
|   | ↳ Aggiungi: **English** (fallback) |

---

### 7️⃣ Jellyfin (Media Server)

> 🔗 `https://jellyfin.mbianchi.me`

| # | Azione |
|---|--------|
| 1 | **Wizard iniziale** |
|   | ↳ Seleziona lingua: Italiano |
|   | ↳ Crea utente admin |
| 2 | **Aggiungi Libreria Film** |
|   | ↳ Tipo: Movies |
|   | ↳ Folder: `/data/movies` |
|   | ↳ Language: Italian |
|   | ↳ Country: Italy |
| 3 | **Aggiungi Libreria Serie TV** |
|   | ↳ Tipo: Shows |
|   | ↳ Folder: `/data/tvshows` |
|   | ↳ Language: Italian |
|   | ↳ Country: Italy |
| 4 | **Aggiungi Libreria Musica** |
|   | ↳ Tipo: Music |
|   | ↳ Folder: `/data/music` |
| 5 | Completa wizard e accedi |

#### Configurazione NVIDIA (Solo GPU NVIDIA)

| # | Azione |
|---|--------|
| 1 | **Dashboard → Playback** |
| 2 | **Transcoding** |
|   | ↳ Hardware acceleration: **NVIDIA NVENC** |
|   | ↳ ✅ Enable hardware decoding for: |
|   | ↳ H264, HEVC, MPEG2, VC1, VP8, VP9, AV1 |
|   | ↳ ✅ Enable hardware encoding |
| 3 | **Save** |

---

## ✅ Verifica Finale

### Test da Terminale

```bash
# 1. Tutti i container attivi?
docker compose ps

# 2. Nginx risponde?
curl -I http://localhost

# 3. Test connettività interna Docker
docker compose exec nginx ping -c 2 sonarr
docker compose exec nginx ping -c 2 radarr
docker compose exec nginx ping -c 2 jellyfin

# 4. Verifica sync Prowlarr
docker compose logs prowlarr | grep -i "sync\|app" | tail -10
```

### Test da Browser

Apri questi URL e verifica che rispondano con HTTPS:
- `https://qbittorrent.mbianchi.me`
- `https://sonarr.mbianchi.me`
- `https://radarr.mbianchi.me`
- `https://jellyfin.mbianchi.me`

---

## 📋 Checklist Finale

### Infrastruttura
- [ ] Docker installato e funzionante
- [ ] Docker Compose installato
- [ ] NVIDIA toolkit installato (se GPU)
- [ ] DNS configurato per *.mbianchi.me
- [ ] Tailscale connesso
- [ ] Cloudflare API token configurato
- [ ] Certificati SSL generati (Tailscale + Let's Encrypt)
- [ ] Firewall configurato
- [ ] Tutti i container in stato "running"

### Servizi
- [ ] qBittorrent: password cambiata
- [ ] Prowlarr: indexer configurati
- [ ] Sonarr: root folder + download client
- [ ] Radarr: root folder + download client
- [ ] Lidarr: root folder + download client
- [ ] Bazarr: collegato a Sonarr/Radarr + provider
- [ ] Jellyfin: librerie create

### Integrazioni
- [ ] Prowlarr → Sonarr connesso
- [ ] Prowlarr → Radarr connesso
- [ ] Prowlarr → Lidarr connesso
- [ ] Bazarr → Sonarr connesso
- [ ] Bazarr → Radarr connesso
- [ ] Hardware transcoding funzionante (se NVIDIA)

---

## 🎉 Fatto!

Il tuo media server è ora completamente configurato e pronto all'uso!

### Prossimi passi

1. **Aggiungi contenuti** - Cerca serie/film in Sonarr/Radarr
2. **Scarica app Jellyfin** - Disponibile per iOS, Android, TV, etc.
3. **Configura utenti** - Crea account per la famiglia in Jellyfin
4. **Monitora** - Controlla periodicamente i log con `docker compose logs -f`

---

<p align="center">
  <b>Buona visione! 🍿</b>
</p>

