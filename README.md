# Toko Arafah Kasir

Aplikasi kasir mainan untuk anak: scan barcode, harga masuk keranjang, lalu
total belanja diumumkan lewat smart speaker.

## Bagian

- `lib/` — aplikasi Flutter (kasir, daftar barang, riwayat, pengaturan)
- `backend/` — backend FastAPI + SQLite untuk STB
- `docs/` — template import dan service systemd

## Alur

1. Scan barcode dengan kamera (atau ketik barcode manual).
2. Barang yang sudah ada langsung masuk keranjang dan harganya diumumkan.
3. Barang baru: aplikasi mencari saran nama dari Open Food/Beauty/Products
   Facts dan saran harga dari internet. Kalau harga tidak ditemukan, dipakai
   estimasi yang wajar dan bisa diubah.
4. Tekan **Bayar** — backend menyimpan transaksi dan mengumumkan total.

## Build APK

Push ke branch `main` akan menjalankan GitHub Actions
(`.github/workflows/build.yml`) dan menghasilkan artifact `tokasrafah-apk`.

## Backend

Lihat [`backend/README.md`](backend/README.md).
