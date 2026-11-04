# Backend Toko Arafah (FastAPI)

Backend kasir sederhana untuk STB. Data disimpan di SQLite `tokasrafah.db`.

## Fitur

- `GET /products/{barcode}` — cari barang (mendukung UPC-A 12 digit maupun 13 digit berawalan 0)
- `POST /products` — tambah barang (JSON: `barcode`, `name`, `price`)
- `PUT /products/{barcode}` — ubah nama/harga
- `POST /checkout` — hitung total, simpan transaksi, dan umumkan total lewat speaker
- `POST /announce/item` — umumkan nama + harga saat barang discan
- `GET /search/suggest?barcode=...` — saran nama dari Open Food/Beauty/Products Facts dan harga dari Open Prices; kalau tidak ada, memakai estimasi wajar
- `POST /import/excel` — import `barcode,nama_barang,harga`

## Suara

Backend memakai API voice-assistant di `VOICE_ASSISTANT_URL` (default
`http://127.0.0.1:8090/speak`) supaya suara memakai TTS Indonesia yang sama
dengan smart speaker. Kalau voice-assistant mati, backend fallback ke Piper
atau espeak-ng.

## Import data

Data awal berasal dari `InventoryItems.xlsx` (hasil scanner: nama, barcode,
timestamp). Hanya barcode dengan checksum GS1 valid yang diimpor.

```bash
cd /opt/tokasrafah
./venv/bin/python import_inventory.py
```

Hasil: 14 barang valid masuk, 3 baris dilewati karena bukan barcode ritel /
checksum tidak valid.

## Menjalankan

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/python app.py
```

Service systemd ada di `docs/tokasrafah.service`.
