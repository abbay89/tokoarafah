# Toko Arafah Kasir

Sistem kasir untuk Toko Arafah yang terdiri dari:
- **Aplikasi Flutter (Android)** — kasir, daftar barang, riwayat transaksi, unduh/cetak resi
- **Backend FastAPI (STB/Raspberry Pi)** — API untuk produk, checkout, TTS suara, pencarian barang dari internet

---

## Arsitektur

```
+---------------------+      HTTP JSON      +-----------------------------+
|  Flutter App (APK)  | <------------------> |  Backend FastAPI (STB)      |
|  - Scan barcode     |      port 8000      |  - SQLite (tokasrafah.db)   |
|  - Keranjang belanja|                     |  - TTS suara (Piper/espeak)   |
|  - Checkout & Resi  |                     |  - Voice assistant (opsional) |
|  - Cetak Bluetooth  |                     +-----------------------------+
+---------------------+
```

---

## 1. Instalasi Backend di STB

Backend berjalan di STB (misal: RK3318 Box / Raspberry Pi) dengan IP `100.101.47.117` pada port `8000`.

### Persyaratan Sistem

- Linux (Debian/Ubuntu/Armbian)
- Python 3.8+
- Speaker / audio output untuk TTS
- Koneksi jaringan (LAN/WiFi)

### Langkah Instalasi

Masuk ke STB melalui SSH double-hop (pertama ke `imac5@192.168.10.156`, lalu ke `root@100.101.47.117`), atau langsung jika STB terhubung jaringan yang sama.

#### A. Install paket sistem

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv ffmpeg alsa-utils pulseaudio espeak-ng
```

#### B. Salin backend ke STB

```bash
APP_DIR=/opt/tokasrafah
sudo mkdir -p "$APP_DIR"
sudo cp -r /path/to/backend/* "$APP_DIR/"
```

Di sini `/path/to/backend/` adalah folder `backend/` dari repo Git ini (`abbay89/tokoarafah`).

#### C. Buat virtualenv dan install dependensi

```bash
cd /opt/tokasrafah
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

#### D. Konfigurasi `.env`

Salin contoh file dan sesuaikan:

```bash
cp .env.example .env
nano .env
```

Contoh isi `.env`:

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

| Variabel | Keterangan |
|----------|------------|
| `PIPER_BIN` | Path binary Piper TTS (jika terinstall) |
| `PIPER_MODEL_ID` | Path ke model suara Indonesia Piper |
| `ESPEAK_BIN` | Binary espeak-ng (fallback TTS) |
| `AUDIO_OUTPUT` | Nama output audio (default/pulse/alsa) |
| `ALSA_DEVICE` | Perangkat ALSA untuk audio |
| `SEARCH_PROVIDER` | `none`, `serpapi`, atau `brave` untuk pencarian harga internet |
| `SERPAPI_KEY` / `BRAVE_KEY` | API key untuk pencarian harga |
| `VOICE_ASSISTANT_URL` | URL voice-assistant eksternal (default `http://127.0.0.1:8090/speak`) |

#### E. Import data barang awal

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

#### E. Jalankan backend secara manual (uji coba)

```bash
./venv/bin/python app.py
```

Backend akan mendengarkan pada `0.0.0.0:8000`. Uji dengan:

```bash
curl http://127.0.0.1:8000/health
# Output: {"status":"ok","service":"tokasrafah"}
```

#### F. Install sebagai service systemd (produksi)

Salin file service:

```bash
sudo cp docs/tokasrafah.service /etc/systemd/system/tokasrafah.service
sudo systemctl daemon-reload
sudo systemctl enable tokasrafah
sudo systemctl start tokasrafah
```

Cek status:

```bash
sudo systemctl status tokasrafah
```

Logs:

```bash
sudo journalctl -u tokasrafah -f
```

---

## 2. Konfigurasi Suara TTS

Backend mendukung tiga metode TTS (urutan prioritas):

1. **Voice Assistant eksternal** (`VOICE_ASSISTANT_URL`) — smart speaker lain yang menanggani `/speak`
2. **Piper TTS** — offline, suara Indonesia natural (perlu model `.onnx`)
3. **espeak-ng** — fallback bawaan sistem

Verifikasi suara TTS:

```bash
# Dari STB itu sendiri
curl http://127.0.0.1:8000/tts/test

# Cek status terakhir
curl http://127.0.0.1:8000/tts/status

# Lihat log semua pemutaran suara
tail -n 20 /opt/tokasrafah/tts.log
```

Setiap transaksi checkout akan otomatis mengumumkan total belanja melalui suara.

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
4. Klik **Tes Koneksi** — harus muncul "Koneksi berhasil: tokasrafah"

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
- Cek log: `tail -n 20 /opt/tokasrafah/tts.log`
- Pastikan speaker terhubung dan volume tidak mati
- Uji manual: `curl http://127.0.0.1:8000/tts/test`

### Masalah: Aplikasi tidak bisa konek ke server
- Pastikan STB menyala dan port 8000 terbuka: `ss -tlnp | grep 8000`
- Pastikan URL di pengaturan aplikasi menggunakan IP yang bisa dijangkau dari Android
- Jika menggunakan WiFi, pastikan Android dan STB di jaringan yang sama

---

## 9. Struktur Repo

```
lib/                  # Kode Flutter (UI, model, service API)
backend/              # Backend FastAPI + SQLite (untuk STB)
  app.py              # Aplikasi backend utama
  import_inventory.py # Skrip impor barang
  requirements.txt    # Dependensi Python
  .env.example        # Contoh konfigurasi environment
docs/                 # Template install STB dan service systemd
  install_stb.sh      # Skrip instalasi otomatis STB
  tokasrafah.service  # File systemd unit
  template_import.xlsx.csv  # Contoh format impor barang
build/                # Hasil build APK (Git LFS)
```

---

## Lisensi

Internal use — Toko Arafah.
