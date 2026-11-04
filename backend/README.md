# Backend Toko Arafah (FastAPI)

Backend kasir untuk STB. Data disimpan di SQLite `tokoarafah.db`. Menyediakan API untuk aplikasi kasir Flutter, termasuk pencarian barang, checkout, dan pengumuman suara TTS.

## Fitur

| Endpoint | Metode | Keterangan |
|----------|--------|------------|
| `/health` | GET | Cek kesiapan server |
| `/products/{barcode}` | GET | Cari barang (mendukung UPC-A 12 digit maupun 13 digit berawalan 0) |
| `/products` | POST | Tambah barang (JSON: `barcode`, `name`, `price`) |
| `/products/{barcode}` | PUT | Ubah nama/harga barang |
| `/checkout` | POST | Hitung total, simpan transaksi, umumkan total lewat speaker |
| `/announce/item` | POST | Umumkan nama + harga saat barang discan |
| `/search/suggest?barcode=...` | GET | Saran nama dari Open Food/Beauty/Products Facts dan harga dari internet; kalau tidak ada, memakai estimasi wajar |
| `/import/excel` | POST | Impor `barcode,nama_barang,harga` dari file Excel |
| `/transactions` | GET | Daftar riwayat transaksi |
| `/tts/test` | GET | Tes suara TTS |
| `/tts/status` | GET | Status TTS terakhir (teks, timestamp, metode) |

## Suara TTS

Backend memakai tiga metode TTS (urutan prioritas):

1. **Voice Assistant eksternal** (`VOICE_ASSISTANT_URL`, default `http://127.0.0.1:8090/speak`) — smart speaker lain yang menangani pemutaran suara
2. **Piper TTS** — offline, suara Indonesia natural (perlu model `.onnx` diunduh secara manual)
3. **espeak-ng** — fallback bawaan sistem

Setiap permintaan TTS dicatat ke `/opt/tokoarafah/tts.log` dengan timestamp, metode, dan detail. Status terakhir bisa dicek via `GET /tts/status`.

## Import Data

Data awal berasal dari `InventoryItems.xlsx` (hasil scanner: nama, barcode, timestamp). Hanya barcode dengan checksum GS1 valid yang diimpor.

Format template impor (`docs/template_import.xlsx.csv`):

```
barcode,nama_barang,harga
8991234567890,Mainan Mobil Anak,50000
8991234567891,Boneka Beruang,75000
8991234567892,Set Dapur Mainan,120000
```

Jalankan impor:

```bash
cd /opt/tokoarafah
./venv/bin/python import_inventory.py
```

## Instalasi di STB (Lengkap)

Lihat [`docs/install_stb.sh`](docs/install_stb.sh) untuk skrip instalasi otomatis, atau ikuti langkah manual di bawah:

### 1. Install paket sistem

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv ffmpeg alsa-utils pulseaudio espeak-ng
```

### 2. Salin backend ke STB

```bash
APP_DIR=/opt/tokoarafah
sudo mkdir -p "$APP_DIR"
sudo cp -r /path/to/backend/* "$APP_DIR/"
```

### 3. Buat virtualenv dan install dependensi

```bash
cd /opt/tokoarafah
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

### 4. Konfigurasi `.env`

```bash
cp .env.example .env
nano .env
```

Contoh:

```
PIPER_BIN=piper
PIPER_MODEL_ID=
ESPEAK_BIN=espeak-ng
AUDIO_OUTPUT=default
ALSA_DEVICE=default
SEARCH_PROVIDER=none
SERPAPI_KEY=
BRAVE_KEY=

VOICE_ASSISTANT_URL=http://127.0.0.1:8090
```

### 5. Uji coba backend

```bash
./venv/bin/python app.py
```

Uji dari terminal lain:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/tts/test
tail -n 5 /opt/tokoarafah/tts.log
```

### 6. Install sebagai service systemd

```bash
sudo cp docs/tokoarafah.service /etc/systemd/system/tokoarafah.service
sudo systemctl daemon-reload
sudo systemctl enable tokoarafah
sudo systemctl start tokoarafah
sudo systemctl status tokoarafah
```

Logs:

```bash
sudo journalctl -u tokoarafah -f
```

## Menjalankan Secara Manual (Pengembangan)

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/python app.py
```

Backend akan mendengarkan pada `0.0.0.0:8000`.

## Verifikasi TTS

```bash
# Tes suara
curl http://127.0.0.1:8000/tts/test

# Cek status terakhir
curl http://127.0.0.1:8000/tts/status

# Lihat log semua suara
tail -n 20 /opt/tokoarafah/tts.log
```

## Database

File SQLite otomatis dibuat di `/opt/tokoarafah/tokoarafah.db` saat backend pertama kali dijalankan. Tabel:
- `products` — daftar barang
- `transactions` — riwayat transaksi
- `transaction_items` — detail item per transaksi
- `search_cache` — cache hasil pencarian dari internet
