# Toko Arafah Kasir

Sistem kasir untuk Toko Arafah yang terdiri dari:
- **Aplikasi Flutter (Android)** — kasir, daftar barang, riwayat transaksi, unduh/cetak resi
- **Backend FastAPI (STB/Raspberry Pi)** — API untuk produk, checkout, TTS suara, pencarian barang dari internet

---

## Arsitektur

```
+---------------------+      HTTP JSON      +-----------------------------+
|  Flutter App (APK)  | <------------------> |  Backend FastAPI (STB / Ubuntu Server)  |
|  - Scan barcode     |      port 8000      |  - SQLite (tokoarafah.db)   |
|  - Keranjang belanja|                     |  - TTS suara (Piper/espeak)   |
|  - Checkout & Resi  |                     |  - Voice assistant (opsional) |
|  - Cetak Bluetooth  |                     +-----------------------------+
+---------------------+
```

---

## 1. Instalasi Backend (STB / Ubuntu Server)

Backend bisa dijalankan di dua jenis mesin:

- **STB** (misal: RK3318 Box / Raspberry Pi / Android TV Box) — biasanya sudah ada speaker bawaan, cocok untuk kasir toko.
- **Ubuntu Server** — server atau PC yang menjalankan Ubuntu Server, cocok jika ingin menjalankan backend di mesin terpisah dari layar kasir.

Keduanya menggunakan kode yang sama. Bedanya hanya pada pemilihan output audio dan cara mengakses mesin.

### Pilihan A: Instalasi di STB

Backend berjalan di STB dengan IP `100.101.47.117` pada port `8000`. Akses melalui SSH double-hop (pertama ke `imac5@192.168.10.156`, lalu ke `root@100.101.47.117`), atau langsung jika STB terhubung jaringan yang sama.

#### A1. Install paket sistem

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv ffmpeg alsa-utils pulseaudio espeak-ng
```

#### A2. Salin backend ke STB

```bash
APP_DIR=/opt/tokoarafah
sudo mkdir -p "$APP_DIR"
sudo cp -r /path/to/backend/* "$APP_DIR/"
```

Di sini `/path/to/backend/` adalah folder `backend/` dari repo Git ini (`abbay89/tokoarafah`).

#### A3. Buat virtualenv dan install dependensi

```bash
cd /opt/tokoarafah
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

#### A4. Konfigurasi `.env`

Salin contoh file dan sesuaikan:

```bash
cp .env.example .env
nano .env
```

Contoh isi `.env` untuk STB:

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

#### A5. Import data barang awal

Jika ada file inventory (Excel/CSV), impor ke database:

```bash
./venv/bin/python import_inventory.py
```

Format file impor (lihat `docs/template_import.xlsx.csv`):

```
barcode,nama_barang,harga
8991234567890,Mainan Mobil Anak,50000
8991234567891,Boneka Beruang,75000
```

#### A6. Jalankan backend secara manual (uji coba)

```bash
./venv/bin/python app.py
```

Backend akan mendengarkan pada `0.0.0.0:8000`. Uji dengan:

```bash
curl http://127.0.0.1:8000/health
# Output: {"status":"ok","service":"tokoarafah"}
```

#### A7. Install sebagai service systemd (produksi)

```bash
sudo cp docs/tokoarafah.service /etc/systemd/system/tokoarafah.service
sudo systemctl daemon-reload
sudo systemctl enable tokoarafah
sudo systemctl start tokoarafah
```

Cek status:

```bash
sudo systemctl status tokoarafah
```

Logs:

```bash
sudo journalctl -u tokoarafah -f
```

---

### Pilihan B: Instalasi di Ubuntu Server

Jika menggunakan Ubuntu Server (misal: VPS, mini PC, atau PC lama yang dipakai sebagai server backend):

#### B1. Install paket sistem

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv ffmpeg alsa-utils pulseaudio espeak-ng
```

#### B2. Clone repo dan masuk ke folder backend

```bash
git clone https://github.com/abbay89/tokoarafah.git
cd tokoarafah/backend
```

#### B3. Buat virtualenv dan install dependensi

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

#### B4. Konfigurasi `.env`

```bash
cp .env.example .env
nano .env
```

Contoh isi `.env` untuk Ubuntu Server (ubah `100.101.47.117` menjadi IP server Anda):

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

#### B5. Jalankan backend

```bash
./venv/bin/python app.py
```

Backend akan mendengarkan pada `0.0.0.0:8000`. Pastikan firewall membuka port 8000:

```bash
sudo ufw allow 8000/tcp
```

Uji dari mesin lain di jaringan yang sama:

```bash
curl http://<IP-UBUNTU-SERVER>:8000/health
```

---

---

## 2. Konfigurasi Suara TTS (Text-to-Speech)

Backend mendukung tiga metode TTS (urutan prioritas):

1. **Voice Assistant eksternal** (`VOICE_ASSISTANT_URL`) — smart speaker lain yang menangani pemutaran suara melalui endpoint `/speak`
2. **Piper TTS** — offline, suara Indonesia natural, cocok untuk STB tanpa koneksi internet (perlu model `.onnx`)
3. **espeak-ng** — fallback bawaan sistem, suara lebih robotis tapi tidak perlu unduh model tambahan

Setiap permintaan TTS dicatat ke `/opt/tokoarafah/tts.log` dengan timestamp, metode, dan detail. Status terakhir bisa dicek via `GET /tts/status`.

### Opsi 1: Piper TTS (disarankan untuk STB)

Piper menghasilkan suara yang lebih natural dan bisa berjalan offline. Langkah instalasi:

#### A. Install Piper

```bash
pip3 install piper-tts
```

Atau unduh binary Piper dari [github.com/rhasspy/piper](https://github.com/rhasspy/piper).

#### B. Unduh model suara Indonesia

Cari model Bahasa Indonesia di repositori Piper, lalu unduh file `.onnx` dan file `.onnx.json`:

```bash
PIPER_MODELS_DIR=/opt/piper_models
mkdir -p "$PIPER_MODELS_DIR"
cd "$PIPER_MODELS_DIR"

# Contoh (ganti dengan URL model Indonesia yang sebenarnya):
# wget https://github.com/rhasspy/piper/releases/download/.../id_ID-vits.onnx
# wget https://github.com/rhasspy/piper/releases/download/.../id_ID-vits.onnx.json
```

Catat path lengkap file `.onnx`, misal: `/opt/piper_models/id_ID-vits.onnx`.

#### C. Konfigurasi `.env`

```bash
nano /opt/tokoarafah/.env
```

Isi:

```
PIPER_BIN=/opt/tokoarafah/venv/bin/piper
PIPER_MODEL_ID=/opt/piper_models/id_ID-vits.onnx
ESPEAK_BIN=espeak-ng
AUDIO_OUTPUT=default
ALSA_DEVICE=default
```

#### D. Restart backend

```bash
sudo systemctl restart tokoarafah
```

#### E. Uji suara Piper

```bash
curl http://127.0.0.1:8000/tts/test
tail -n 5 /opt/tokoarafah/tts.log
# Harus menampilkan: method=piper detail=ok
```

### Opsi 2: espeak-ng (fallback, tidak perlu unduh model)

espeak-ng biasanya sudah terinstall setelah `apt-get install espeak-ng`. Konfigurasi `.env`:

```
PIPER_BIN=
PIPER_MODEL_ID=
ESPEAK_BIN=espeak-ng
AUDIO_OUTPUT=default
ALSA_DEVICE=default
```

Restart backend dan uji:

```bash
sudo systemctl restart tokoarafah
curl http://127.0.0.1:8000/tts/test
```

### Opsi 3: Voice Assistant eksternal

Jika ada smart speaker atau mesin lain yang menyediakan endpoint TTS, isi `VOICE_ASSISTANT_URL`:

```
VOICE_ASSISTANT_URL=http://<IP-VOICE-ASSISTANT>:8090/speak
```

Backend akan mencoba mengirim teks ke URL tersebut. Jika gagal, akan fallback ke Piper atau espeak-ng.

### Verifikasi Suara TTS

```bash
# Dari STB / Ubuntu Server itu sendiri
curl http://127.0.0.1:8000/tts/test

# Cek status terakhir (teks, timestamp, metode)
curl http://127.0.0.1:8000/tts/status

# Lihat log semua pemutaran suara
tail -n 20 /opt/tokoarafah/tts.log
```

Contoh output `tts.log`:

```
[2026-11-04T11:22:19.645599] method=voice-assistant text='Total belanja tiga puluh tiga ribu lima ratus rupiah' detail=ok
[2026-11-04T11:22:13.463053] method=piper text='Pomade Hitam, harga dua puluh tiga ribu rupiah' detail=ok
```

Setiap transaksi checkout akan otomatis mengumumkan total belanja melalui suara.

Setiap barang yang discan juga akan diumumkan namanya dan harganya.

---

## 3. Instalasi Aplikasi Flutter (Android)

### Dari APK (tercepat)

Unduh file `app-debug.apk` dari branch `main` repo ini (disimpan via Git LFS di `build/app/outputs/apk/debug/app-debug.apk`), lalu instal di Android:

```bash
adb install -r app-debug.apk
```

Atau buka file APK di pengelola file Android dan klik untuk install.

### Build sendiri dari source

```bash
# Install Flutter SDK (https://docs.flutter.dev/get-started/install)
flutter --version

cd /path/to/repo
flutter pub get
flutter build apk --debug
```

APK hasil build ada di `build/app/outputs/apk/debug/app-debug.apk`.

---

## 4. Konfigurasi Aplikasi

Setelah instalasi pertama kali:

1. Buka aplikasi **Toko Arafah Kasir**
2. Buka menu **Pengaturan**
3. Masukkan **Alamat Server STB**, contoh:
   - `http://100.101.47.117:8000`
   - atau `http://192.168.18.240:8000` (jika di LAN yang sama)
4. Klik **Tes Koneksi** — harus muncul "Koneksi berhasil: tokoarafah"

---

## 5. Penggunaan Aplikasi

### Menu Kasir

1. **Scan barcode** — arahkan kamera ke barcode produk, atau ketik barcode manual di kolom bawah
2. Barang yang dikenal akan langsung masuk ke keranjang dan harganya diumumkan lewat suara
3. Barang baru akan memunculkan dialog input harga
4. Tekan **Bayar** untuk checkout
5. Setelah pembayaran selesai, pilih:
   - **Unduh Resi (PDF)** — simpan file resi ke folder Downloads
   - **Cetak Bluetooth** — cetak ke printer Bluetooth ESC/POS (harus dipilih printer dulu)
   - **Tutup**

### Menu Barang

- Lihat daftar semua barang
- Tekan **+** (tambah) untuk menambah barang baru — ada ikon scanner barcode untuk mengisi field barcode secara otomatis
- Edit atau hapus barang yang ada

### Menu Riwayat

- Lihat daftar semua transaksi yang sudah checkout
- Geser ke bawah untuk refresh (pull-to-refresh)
- Setiap transaksi menampilkan total dan daftar item

### Menu Pengaturan

- Atur alamat server STB
- Tes koneksi ke backend

---

## 6. Konfigurasi Printer Bluetooth (Opsional)

Untuk mencetak resi ke printer laser Bluetooth (protokol ESC/POS):

1. Pastikan printer sudah **terpair** dengan perangkat Android melalui pengaturan Bluetooth sistem
2. Buka menu Kasir, lakukan checkout minimal satu transaksi
3. Pilih **Cetak Bluetooth** — aplikasi akan meminta memilih printer dari daftar terpair
4. Pilih printer, kemudian cetak resi

Alamat printer disimpan otomatis untuk sesi berikutnya.

---

## 7. Endpoint Backend (Referensi)

| Endpoint | Metode | Keterangan |
|----------|--------|------------|
| `/health` | GET | Cek kesiapan server |
| `/products/{barcode}` | GET | Cari barang menurut barcode |
| `/products` | POST | Tambah barang baru |
| `/products/{barcode}` | PUT | Ubah nama/harga barang |
| `/checkout` | POST | Simpan transaksi + umumkan total lewat suara |
| `/announce/item` | POST | Umumkan nama + harga barang |
| `/search/suggest?barcode=...` | GET | Saran nama & harga dari internet |
| `/import/excel` | POST | Impor barang dari file Excel |
| `/transactions` | GET | Daftar riwayat transaksi |
| `/tts/test` | GET | Tes suara TTS |
| `/tts/status` | GET | Status TTS terakhir |

---

## 8. Verifikasi & Troubleshooting

### Masalah: Menu riwayat kosong
- Pastikan URL server di pengaturan aplikasi sudah benar (`http://100.101.47.117:8000`)
- Pastikan sudah ada setidaknya satu transaksi checkout yang berhasil
- Uji endpoint langsung dari STB: `curl http://127.0.0.1:8000/transactions`

### Masalah: Suara TTS tidak keluar

**Untuk STB:**
- Cek log: `tail -n 20 /opt/tokoarafah/tts.log`
- Pastikan speaker terhubung dan volume tidak mati
- Uji manual: `curl http://127.0.0.1:8000/tts/test`
- Pastikan `PIPER_MODEL_ID` menunjuk ke file `.onnx` yang valid (jika menggunakan Piper)
- Pastikan `espeak-ng` terinstall: `which espeak-ng`

**Untuk Ubuntu Server (tanpa speaker bawaan):**
- Ubuntu Server biasanya tidak memiliki audio hardware. Pasang speaker USB atau gunakan output HDMI.
- Cek perangkat audio: `aplay -l` atau `pactl list sinks`
- Jika tidak ada perangkat audio, gunakan opsi **Voice Assistant eksternal** (kirim TTS ke smart speaker lain) atau instal di STB yang memiliki speaker.
- Uji output audio: `aplay /usr/share/sounds/alsa/Front_Center.wav`

### Masalah: Aplikasi tidak bisa konek ke server
- Pastikan STB / Ubuntu Server menyala dan port 8000 terbuka: `ss -tlnp | grep 8000`
- Pastikan URL di pengaturan aplikasi menggunakan IP yang bisa dijangkau dari Android
- Jika menggunakan Ubuntu Server, pastikan firewall membuka port 8000: `sudo ufw allow 8000/tcp`
- Jika menggunakan WiFi, pastikan Android dan server di jaringan yang sama

---

## 9. Struktur Repo

```
lib/                  # Kode Flutter (UI, model, service API)
backend/              # Backend FastAPI + SQLite (untuk STB / Ubuntu Server)
  app.py              # Aplikasi backend utama
  import_inventory.py # Skrip impor barang
  requirements.txt    # Dependensi Python
  .env.example        # Contoh konfigurasi environment
docs/                 # Template install STB / Ubuntu Server dan service systemd
  install_stb.sh      # Skrip instalasi otomatis STB
  tokoarafah.service  # File systemd unit
  template_import.xlsx.csv  # Contoh format impor barang
build/                # Hasil build APK (Git LFS)
```

---

## Lisensi

Internal use — Toko Arafah.
