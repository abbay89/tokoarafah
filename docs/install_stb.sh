#!/bin/bash
set -e

echo "==> Update paket sistem"
apt-get update
apt-get install -y python3 python3-pip python3-venv ffmpeg alsa-utils pulseaudio espeak-ng

echo "==> Install Piper TTS (offline Bahasa Indonesia)"
pip3 install piper-tts || true

echo "==> Unduh model suara Indonesia Piper (contoh: ID - female)"
PIPER_MODELS_DIR=/opt/piper_models
mkdir -p "$PIPER_MODELS_ID"
cd "$PIPER_MODELS_DIR"
# Ganti URL/model dengan model Indonesia resmi Piper jika tersedia
# Contoh placeholder; sesuaikan dengan model yang tersedia di https://github.com/rhasspy/piper
echo "Model Piper harus diunduh secara manual dan diatur di .env (PIPER_MODEL_ID)"

echo "==> Buat direktori aplikasi"
APP_DIR=/opt/tokasrafah
mkdir -p "$APP_DIR"
cp -r /vagrant/backend/* "$APP_DIR/" 2>/dev/null || cp -r /mnt/data/backend/* "$APP_DIR/" 2>/dev/null || true

echo "==> Buat virtualenv dan install deps"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"

echo "==> Salin .env.example ke .env (isi API key search jika ada)"
cp "$APP_DIR/.env.example" "$APP_DIR/.env"

echo "==> Buat user sistem (opsional)"
id tokasrafah 2>/dev/null || useradd -r -s /bin/false tokasrafah
chown -R tokasrafah:tokasrafah "$APP_DIR"

echo "==> Selesai. Konfigurasi /etc/systemd/system/tokasrafah.service lalu jalankan:"
