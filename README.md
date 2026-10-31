# Toko Arafah - Sistem Kasir Mainan Anak

## Arsitektur
- **Backend:** Python FastAPI + SQLite, berjalan di STB (Armbian/Linux ARM), port 8000.
- **APK:** Flutter Android, client kasir, TTS diputar di speaker STB via ALSA/PulseAudio.

## 1. Instalasi Backend di STB

```bash
# Di STB (Armbian/Linux), login sebagai root atau sudo
apt-get update && apt-get install -y python3 python3-pip python3-venv ffmpeg alsa-utils pulseaudio espeak-ng

# Clone/kopi folder backend ke /opt/tokasrafah
mkdir -p /opt/tokasrafah
# salin isi folder backend ke sini

cd /opt/tokasrafah
python3 -m venv venv
./venv/bin/pip install -r requirements.txt

# Konfigurasi .env (Piper model, API key search, audio output)
cp .env.example .env
nano .env

# Install service systemd
sudo cp tokasrafah.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tokasrafah.service

# Cek status
sudo systemctl status tokasrafah.service
curl http://192.168.18.240:8000/health
```

Pastikan STB bisa diakses via LAN, misal `http://192.168.18.240:8000`.

## 2. Konfigurasi Suara (TTS)

TTS diputar di speaker STB, bukan di HP.

- **Piper TTS (utama, offline):** isi `PIPER_BIN` dan `PIPER_MODEL_ID` di `.env`. Unduh model suara Indonesia dari repository Piper.
- **Fallback espeak-ng:** `espeak-ng -v id` (sudah diinstall via apt).
- Audio lewat ALSA/PulseAudio (`aplay` / `mpv`). Atur `ALSA_DEVICE` di `.env` jika perlu.

Endpoint tes suara: `POST /speak` dengan body `{"text": "Tes suara Toko Arafah"}`.

## 3. Instalasi APK (Flutter)

## 4. API Ringkas

- `GET /health`
- `GET /products/{barcode}`
- `GET /products?search=&missing_price=`
- `POST /products`
- `PUT /products/{barcode}`
- `DELETE /products/{barcode}`
- `POST /import/excel` (multipart file)
- `GET /search/suggest?barcode=&name=`
- `POST /speak` `{"text": "..."}`
- `POST /checkout` `{"items": [{"barcode": "...", "qty": 1}]}`
- `GET /transactions?date=`

## 5. Template Excel

Buat file `.xlsx` dengan header:
- `barcode` (teks, wajib)
- `nama_barang` (wajib)
- `harga` (opsional, integer)

Contoh:
| barcode | nama_barang | harga |
|---------|-------------|-------|
| 8991234567890 | Mainan Mobil | 50000 |
| 8991234567891 | Boneka | 75000 |

## 6. Troubleshooting Suara Tidak Keluar

1. Pastikan speaker terhubung ke STB (3.5mm jack / USB audio / HDMI).
2. Cek output audio: `aplay -l` dan `pactl list sinks`.
3. Test manual: `aplay /usr/share/sounds/alsa/Front_Center.wav` atau `espeak-ng -v id "tes"`.
4. Pastikan `ALSA_DEVICE` di `.env` sesuai dengan nama device aplay.
5. Cek log service: `journalctl -u tokasrafah -f`.
6. Endpoint tes: `curl -X POST http://192.168.18.24:8000/speak -H "Content-Type: application/json" -d '{"text":"Tes suara"}'`.

## 7. Catatan IP Lokal

Contoh IP STB: `192.168.18.24`. Sesuaikan dengan IP sebenarnya di APK Pengaturan.
