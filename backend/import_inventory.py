#!/usr/bin/env python3
"""Import barang valid dari InventoryItems.xlsx ke database Toko Arafah.

File asli dari aplikasi scanner hanya berisi: nama, barcode, timestamp.
Skrip ini:
- hanya mengambil barcode yang lolos checksum GS1 (EAN-8/UPC-A/EAN-13/GTIN-14)
- merapikan nama barang
- mengisi harga (kurasi untuk barang yang dikenal, estimasi untuk sisanya)
- upsert ke tabel products
"""
import csv
import sys
from pathlib import Path

sys.path.insert(0, "/opt/tokasrafah")

import openpyxl

from app import (
    barcode_checksum_ok,
    barcode_kind,
    estimate_price,
    get_db,
    normalize_barcode,
)

SRC = Path("/opt/tokasrafah/InventoryItems.xlsx")
OUT_CSV = Path("/opt/tokasrafah/inventory_clean.csv")

# Harga ramah anak/mainan kasiran (Rupiah). Bisa diubah kapan saja dari aplikasi.
PRICE_MAP = {
    "8992772265164": 15000,   # Antis
    "8998103015262": 12000,   # Minyak Rambut
    "8997023620723": 25000,   # Minyak Hijau / Minyak Herba Sinergi
    "711844120037": 12500,    # ABC Sambal Asli 130 ml
    "8999999615635": 20000,   # Resona
    "8714700524002": 6000,    # Maizenaku
    "8886451002891": 120000,  # Susu Pediasure Madu
    "8993391311935": 5000,    # Cuka
    "8886030642944": 10000,   # Dee-Dee
    "8995227500124": 5000,    # Cap Kaki Tiga 200 ml
    "8998866109444": 12000,   # Lovely
    "8993120200356": 5000,    # Gas Refill
    "8992745610526": 15000,   # Stella
    "8999908208101": 12000,   # Bedak My Baby
}

NAME_MAP = {
    "antis": "Antis",
    "miyak rambut": "Minyak Rambut",
    "miyak ijo": "Minyak Hijau",
    "abc sambal asli": "ABC Sambal Asli",
    "resona": "Resona",
    "maizenaku": "Maizenaku",
    "susu pedia sure": "Susu Pediasure",
    "cuka": "Cuka",
    "dee-dee": "Dee-Dee",
    "cap kaki tiga kali": "Cap Kaki Tiga",
    "lovely": "Lovely",
    "gas re fill": "Gas Refill",
    "stella": "Stella",
    "bedak my baby": "Bedak My Baby",
}


def clean_name(raw: str) -> str:
    key = " ".join(str(raw or "").strip().lower().split())
    return NAME_MAP.get(key, " ".join(str(raw or "").strip().split()).title())


def main() -> None:
    wb = openpyxl.load_workbook(SRC, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))

    valid, invalid = [], []
    for row in rows:
        name = str(row[0] or "").strip()
        barcode = normalize_barcode(row[1])
        if not name or not barcode:
            continue
        if not barcode_checksum_ok(barcode):
            invalid.append((name, barcode, barcode_kind(barcode) or "bukan barcode ritel"))
            continue
        clean = clean_name(name)
        price = PRICE_MAP.get(barcode) or estimate_price(barcode, clean)
        valid.append({
            "barcode": barcode,
            "nama_barang": clean,
            "harga": price,
            "jenis": barcode_kind(barcode),
        })

    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["barcode", "nama_barang", "harga"])
        writer.writeheader()
        for item in valid:
            writer.writerow({k: item[k] for k in ("barcode", "nama_barang", "harga")})

    conn = get_db()
    added = updated = 0
    for item in valid:
        existing = conn.execute(
            "SELECT barcode FROM products WHERE barcode = ?", (item["barcode"],)
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE products SET name = ?, price = ?, updated_at = datetime('now') WHERE barcode = ?",
                (item["nama_barang"], item["harga"], item["barcode"]),
            )
            updated += 1
        else:
            conn.execute(
                "INSERT INTO products (barcode, name, price, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))",
                (item["barcode"], item["nama_barang"], item["harga"]),
            )
            added += 1
    conn.commit()
    conn.close()

    print(f"Valid  : {len(valid)} (ditambah {added}, diperbarui {updated})")
    print(f"Invalid: {len(invalid)} (dilewati)")
    for name, barcode, reason in invalid:
        print(f"  - {name}: {barcode} -> {reason}")
    print(f"CSV bersih: {OUT_CSV}")


if __name__ == "__main__":
    main()
