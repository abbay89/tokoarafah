import os
import re
import json
import random
import hashlib
import sqlite3
import subprocess
import tempfile
import logging
from pathlib import Path
from typing import List, Optional, Dict, Any
from datetime import datetime
import threading
from threading import Lock

import requests
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tokasrafah")

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "tokasrafah.db"
ENV_PATH = BASE_DIR / ".env"

app = FastAPI(title="Toko Arafah Kasir Backend")

voice_lock = Lock()
tts_lock = Lock()
tts_log_path = BASE_DIR / "tts.log"
last_spoken = {"text": None, "timestamp": None, "method": None}


def tts_log(text: str, method: str, detail: str = "") -> None:
    """Catat setiap permintaan TTS ke file log dengan timestamp."""
    ts = datetime.now().isoformat()
    line = f"[{ts}] method={method} text={text!r} detail={detail}\n"
    try:
        with tts_lock:
            with open(tts_log_path, "a", encoding="utf-8") as f:
                f.write(line)
    except Exception as exc:
        logger.warning("Gagal menulis log TTS: %s", exc)


def set_last_spoken(text: str, method: str) -> None:
    """Simpan teks terakhir diucapkan (thread-safe)."""
    with tts_lock:
        last_spoken["text"] = text
        last_spoken["timestamp"] = datetime.now().isoformat()
        last_spoken["method"] = method


def load_env() -> dict:
    env = {}
    if ENV_PATH.exists():
        with open(ENV_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    return env


ENV = load_env()


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS products (
            barcode TEXT PRIMARY KEY,
            name TEXT,
            price INTEGER,
            created_at TEXT,
            updated_at TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total INTEGER,
            created_at TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS transaction_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER,
            barcode TEXT,
            name TEXT,
            price INTEGER,
            qty INTEGER,
            FOREIGN KEY(transaction_id) REFERENCES transactions(id)
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS search_cache (
            barcode TEXT PRIMARY KEY,
            name TEXT,
            price_suggestions TEXT,
            recommended_price INTEGER,
            source TEXT,
            created_at TEXT
        )
    """)
    # Migrasi untuk database lama yang belum punya kolom baru.
    cols = {r[1] for r in c.execute("PRAGMA table_info(search_cache)").fetchall()}
    if "recommended_price" not in cols:
        c.execute("ALTER TABLE search_cache ADD COLUMN recommended_price INTEGER")
    if "source" not in cols:
        c.execute("ALTER TABLE search_cache ADD COLUMN source TEXT")
    conn.commit()
    conn.close()


init_db()


# ---------------------------------------------------------------------------
# Barcode helpers
# ---------------------------------------------------------------------------

def normalize_barcode(raw: Optional[str]) -> str:
    """Barcode disimpan apa adanya (string), hanya spasi tepi yang dibuang.

    Leading zero penting untuk EAN-8/UPC-A, jadi jangan pernah di-cast ke int.
    """
    return str(raw or "").strip()


def barcode_kind(barcode: str) -> Optional[str]:
    if not barcode.isdigit():
        return None
    return {8: "EAN-8", 12: "UPC-A", 13: "EAN-13", 14: "GTIN-14"}.get(len(barcode))


def barcode_checksum_ok(barcode: str) -> bool:
    """Validasi checksum GS1 untuk EAN-8, UPC-A, EAN-13, dan GTIN-14."""
    if not barcode.isdigit() or len(barcode) not in (8, 12, 13, 14):
        return False
    body, check = barcode[:-1], int(barcode[-1])
    total = 0
    for i, ch in enumerate(reversed(body)):
        total += int(ch) * (3 if i % 2 == 0 else 1)
    return (10 - total % 10) % 10 == check


def barcode_variants(barcode: str) -> List[str]:
    """Scanner kadang mengirim UPC-A sebagai 12 digit, kadang 13 digit berawalan 0."""
    bc = normalize_barcode(barcode)
    variants = [bc]
    if bc.isdigit():
        if len(bc) == 13 and bc.startswith("0"):
            variants.append(bc[1:])
        elif len(bc) == 12:
            variants.append("0" + bc)
        elif len(bc) == 14 and bc.startswith("0"):
            variants.append(bc[1:])
    return list(dict.fromkeys(variants))


def find_product(conn: sqlite3.Connection, barcode: str):
    for candidate in barcode_variants(barcode):
        row = conn.execute("SELECT * FROM products WHERE barcode = ?", (candidate,)).fetchone()
        if row:
            return row
    return None


# ---------------------------------------------------------------------------
# Saran nama & harga dari internet
# ---------------------------------------------------------------------------

OPEN_FACTS_SOURCES = [
    ("https://world.openfoodfacts.org", "Open Food Facts"),
    ("https://world.openbeautyfacts.org", "Open Beauty Facts"),
    ("https://world.openproductsfacts.org", "Open Products Facts"),
]

# Rentang harga mainan/kasiran (Rupiah). Dipakai hanya bila harga pasar
# benar-benar tidak ditemukan di internet.
PRICE_RANGES = [
    (("pediasure", "susu bayi", "susu formula"), 85000, 150000),
    (("susu", "milk"), 8000, 35000),
    (("minyak", "kayu putih", "rambut", "hijau", "angin", "herba"), 10000, 30000),
    (("sambal", "saus", "kecap", "mayonaise"), 8000, 20000),
    (("cuka", "gas", "korek"), 3000, 10000),
    (("bedak", "deodorant", "deodoran", "lovely", "stella", "antis", "sabun"), 8000, 25000),
    (("maizena", "tepung", "gula", "garam", "bumbu"), 4000, 15000),
    (("snack", "dee-dee", "biskuit", "keripik", "makanan"), 7000, 20000),
    (("minuman", "teh", "kopi", "air", "cap kaki tiga"), 4000, 15000),
]

ESTIMATE_MIN = 5000
ESTIMATE_MAX = 50000


def _http_json(url: str, params: Optional[dict] = None, timeout: float = 8.0):
    try:
        r = requests.get(
            url,
            params=params,
            timeout=timeout,
            headers={"User-Agent": "tokasrafah-kasir/1.0 (toy cashier)"},
        )
        if r.status_code == 200:
            return r.json()
    except Exception as exc:
        logger.info("Lookup internet gagal (%s): %s", url, exc)
    return None


def lookup_open_facts(barcode: str) -> Optional[Dict[str, Any]]:
    """Cari nama produk dari database Open Food/Beauty/Products Facts (gratis)."""
    bc = normalize_barcode(barcode)
    if not bc or not bc.isdigit():
        return None
    for base_url, source in OPEN_FACTS_SOURCES:
        data = _http_json(
            f"{base_url}/api/v2/product/{bc}.json",
            {"fields": "product_name,product_name_id,generic_name,brands,categories,quantity,product_quantity"},
        )
        if not data or data.get("status") != 1:
            continue
        p = data.get("product") or {}
        name = " ".join(
            str(p.get(key) or "").strip()
            for key in ("product_name", "product_name_id", "generic_name")
        ).strip()
        if not name:
            name = str(p.get("brands") or "").strip()
        if not name:
            continue
        return {
            "name": name,
            "brands": str(p.get("brands") or "").strip() or None,
            "categories": str(p.get("categories") or "").strip() or None,
            "quantity": str(p.get("quantity") or p.get("product_quantity") or "").strip() or None,
            "source": source,
        }
    return None


def lookup_open_prices(barcode: str) -> Optional[int]:
    """Ambil harga IDR dari Open Prices (data komunitas, gratis)."""
    bc = normalize_barcode(barcode)
    if not bc:
        return None
    data = _http_json(
        "https://prices.openfoodfacts.org/api/v1/prices",
        {"product_code": bc, "size": 20},
    )
    if not data:
        return None
    prices = []
    for item in data.get("items") or []:
        try:
            if str(item.get("currency") or "").upper() != "IDR":
                continue
            value = float(item.get("price"))
            if value > 0:
                prices.append(int(round(value)))
        except Exception:
            continue
    if not prices:
        return None
    prices.sort()
    return prices[len(prices) // 2]


def price_range_for_name(name: Optional[str]) -> tuple:
    text = (name or "").lower()
    for keywords, low, high in PRICE_RANGES:
        if any(k in text for k in keywords):
            return low, high
    return ESTIMATE_MIN, ESTIMATE_MAX


def estimate_price(barcode: str, name: Optional[str] = None) -> int:
    """Harga estimasi deterministik: barcode sama selalu dapat harga sama.

    Untuk mainan kasir, harga acak yang wajar lebih baik daripada Rp0.
    """
    low, high = price_range_for_name(name)
    seed_src = f"{normalize_barcode(barcode)}|{(name or '').lower()}".encode("utf-8")
    rnd = random.Random(int(hashlib.sha256(seed_src).hexdigest()[:16], 16))
    step = 500
    price = rnd.randrange(low, high + step, step)
    return max(step, price)


def _parse_price_text(value: Any) -> Optional[int]:
    text = str(value or "")
    matches = re.findall(r"(?:Rp\s*)?([\d][\d\.\,]{2,})", text, flags=re.IGNORECASE)
    for raw in matches:
        cleaned = raw.replace(".", "").replace(",", "")
        try:
            price = int(cleaned)
        except Exception:
            continue
        if 500 <= price <= 50_000_000:
            return price
    return None


def search_web_prices(query: str) -> List[Dict[str, str]]:
    """Cari harga lewat SerpAPI/Brave kalau API key diisi di .env."""
    env = load_env()
    provider = env.get("SEARCH_PROVIDER", "none").lower()
    suggestions: List[Dict[str, str]] = []
    try:
        if provider == "serpapi" and env.get("SERPAPI_KEY"):
            r = requests.get(
                "https://serpapi.com/search.json",
                params={
                    "q": query,
                    "api_key": env["SERPAPI_KEY"],
                    "engine": "google",
                    "gl": "id",
                    "hl": "id",
                },
                timeout=15,
            )
            data = r.json()
            for res in (data.get("shopping_results") or [])[:5]:
                suggestions.append({
                    "source": res.get("source", "SerpAPI"),
                    "title": res.get("title", ""),
                    "price": res.get("price", ""),
                })
        elif provider == "brave" and env.get("BRAVE_KEY"):
            r = requests.get(
                "https://api.search.brave.com/res/v1/web/search",
                headers={"X-Subscription-Token": env["BRAVE_KEY"]},
                params={"q": query, "count": 5},
                timeout=15,
            )
            data = r.json()
            for res in (data.get("web", {}).get("results") or [])[:5]:
                suggestions.append({
                    "source": res.get("source", "Brave"),
                    "title": res.get("title", ""),
                    "price": "",
                })
    except Exception as exc:
        logger.warning("Pencarian harga web gagal: %s", exc)
    return suggestions


class ProductIn(BaseModel):
    barcode: Optional[str] = None
    name: Optional[str] = None
    price: Optional[int] = None


class ProductOut(BaseModel):
    barcode: str
    name: Optional[str]
    price: Optional[int]
    created_at: Optional[str]
    updated_at: Optional[str]


class CheckoutItem(BaseModel):
    barcode: str
    qty: int


class CheckoutIn(BaseModel):
    items: List[CheckoutItem]


class SpeakIn(BaseModel):
    text: str


class AnnounceItemIn(BaseModel):
    name: str
    price: int


def number_to_id_words(n: int) -> str:
    if n < 0:
        return "min " + number_to_id_words(-n)
    if n == 0:
        return "nol"
    satuan = ["", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh", "delapan", "sembilan"]
    belasan = ["", "sebelas", "dua belas", "tiga belas", "empat belas", "lima belas", "enam belas", "tujuh belas", "delapan belas", "sembilan belas"]

    def convert_under_thousand(val: int) -> str:
        if val == 0:
            return ""
        if val < 10:
            return satuan[val]
        if val < 20:
            return belasan[val - 10]
        if val < 100:
            puluh = val // 10
            sisa = val % 10
            if puluh == 1:
                return "sepuluh" + (" " + satuan[sisa] if sisa else "")
            kata = satuan[puluh] + " puluh"
            if sisa:
                kata += " " + satuan[sisa]
            return kata
        ratus = val // 100
        sisa = val % 100
        kata = "seratus" if ratus == 1 else satuan[ratus] + " ratus"
        if sisa:
            kata += " " + convert_under_thousand(sisa)
        return kata

    if n < 1000:
        return convert_under_thousand(n)
    ribuan = n // 1000
    sisa = n % 1000
    if ribuan == 1:
        kata = "seribu"
    else:
        kata = convert_under_thousand(ribuan) + " ribu"
    if sisa:
        kata += " " + convert_under_thousand(sisa)
    return kata


@app.get("/health")
def health():
    return {"status": "ok", "service": "tokasrafah"}


@app.get("/products/{barcode}", response_model=ProductOut)
def get_product(barcode: str):
    conn = get_db()
    row = find_product(conn, barcode)
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    return dict(row)


@app.get("/products", response_model=List[ProductOut])
def list_products(search: Optional[str] = None, missing_price: bool = False):
    conn = get_db()
    q = "SELECT * FROM products"
    params = []
    conds = []
    if search:
        conds.append("(name LIKE ? OR barcode LIKE ?)")
        params.extend([f"%{search}%", f"%{search}%"])
    if missing_price:
        conds.append("price IS NULL")
    if conds:
        q += " WHERE " + " AND ".join(conds)
    q += " ORDER BY name IS NULL, name"
    rows = conn.execute(q, params).fetchall()
    conn.close()
    return [dict(r) for r in rows]


@app.post("/products", response_model=ProductOut)
def create_product(p: ProductIn):
    barcode = normalize_barcode(p.barcode)
    if not barcode:
        raise HTTPException(status_code=400, detail="Barcode wajib diisi")
    if p.price is not None and p.price < 0:
        raise HTTPException(status_code=400, detail="Harga tidak boleh negatif")
    conn = get_db()
    if find_product(conn, barcode):
        conn.close()
        raise HTTPException(status_code=409, detail="Barcode sudah ada")
    now = datetime.utcnow().isoformat()
    conn.execute(
        "INSERT INTO products (barcode, name, price, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        (barcode, p.name, p.price, now, now),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM products WHERE barcode = ?", (barcode,)).fetchone()
    conn.close()
    return dict(row)


@app.put("/products/{barcode}", response_model=ProductOut)
def update_product(barcode: str, p: ProductIn):
    if p.price is not None and p.price < 0:
        raise HTTPException(status_code=400, detail="Harga tidak boleh negatif")
    conn = get_db()
    row = find_product(conn, barcode)
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    now = datetime.utcnow().isoformat()
    name = p.name if p.name is not None else row["name"]
    price = p.price if p.price is not None else row["price"]
    conn.execute(
        "UPDATE products SET name = ?, price = ?, updated_at = ? WHERE barcode = ?",
        (name, price, now, row["barcode"]),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM products WHERE barcode = ?", (row["barcode"],)).fetchone()
    conn.close()
    return dict(row)


@app.delete("/products/{barcode}")
def delete_product(barcode: str):
    conn = get_db()
    row = find_product(conn, barcode)
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    conn.execute("DELETE FROM products WHERE barcode = ?", (row["barcode"],))
    conn.commit()
    conn.close()
    return {"detail": "Produk dihapus"}


@app.post("/checkout")
def checkout(inp: CheckoutIn):
    if not inp.items:
        raise HTTPException(status_code=400, detail="Keranjang kosong")
    for item in inp.items:
        if item.qty <= 0:
            raise HTTPException(status_code=400, detail="Jumlah barang harus lebih dari 0")

    conn = get_db()
    resolved = []
    missing_price = []
    for item in inp.items:
        row = find_product(conn, item.barcode)
        if not row:
            conn.close()
            raise HTTPException(status_code=404, detail=f"Produk {item.barcode} tidak ditemukan")
        if row["price"] is None:
            missing_price.append(f"{row['name'] or row['barcode']} ({row['barcode']})")
            continue
        resolved.append((row, item.qty))
    if missing_price:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail="Harga belum diisi untuk: " + ", ".join(missing_price),
        )

    total = sum(int(row["price"]) * qty for row, qty in resolved)
    now = datetime.utcnow().isoformat()
    cur = conn.execute("INSERT INTO transactions (total, created_at) VALUES (?, ?)", (total, now))
    tx_id = cur.lastrowid
    for row, qty in resolved:
        conn.execute(
            "INSERT INTO transaction_items (transaction_id, barcode, name, price, qty) VALUES (?, ?, ?, ?, ?)",
            (tx_id, row["barcode"], row["name"], int(row["price"]), qty),
        )
    conn.commit()
    conn.close()

    total_words = number_to_id_words(total)
    text = f"Total belanja {total_words} rupiah"
    speak_queue(text)
    return {"transaction_id": tx_id, "total": total, "total_words": total_words, "text": text}


@app.get("/transactions")
def get_transactions(date: Optional[str] = None):
    conn = get_db()
    if date:
        rows = conn.execute(
            "SELECT * FROM transactions WHERE date(created_at) = date(?) ORDER BY created_at DESC",
            (date,),
        ).fetchall()
    else:
        rows = conn.execute("SELECT * FROM transactions ORDER BY created_at DESC").fetchall()
    result = []
    for r in rows:
        items = conn.execute(
            "SELECT * FROM transaction_items WHERE transaction_id = ?", (r["id"],)
        ).fetchall()
        result.append({
            "id": r["id"],
            "total": r["total"],
            "created_at": r["created_at"],
            "items": [dict(i) for i in items],
        })
    conn.close()
    return result


def speak_queue(text: str):
    def _speak():
        with voice_lock:
            _speak_once(text)
    threading.Thread(target=_speak, daemon=True).start()


def _speak_via_assistant(text: str) -> bool:
    """Pakai API voice-assistant (edge TTS, suara Indonesia natural).

    Voice assistant yang sama juga dipakai smart speaker di rumah, jadi
    volume, jeda musik, dan echo-guard-nya sudah ditangani di sana.
    """
    env = load_env()
    base = env.get("VOICE_ASSISTANT_URL", "http://127.0.0.1:8080").strip()
    if not base:
        return False
    try:
        r = requests.post(
            base.rstrip("/") + "/speak",
            json={"text": text},
            timeout=6,
        )
        if r.status_code < 400:
            logger.info("TTS via voice-assistant: %s", text)
            tts_log(text, "voice-assistant", "ok")
            set_last_spoken(text, "voice-assistant")
            return True
        logger.warning("Voice assistant menolak TTS (%s): %s", r.status_code, r.text[:200])
        tts_log(text, "voice-assistant", f"rejected {r.status_code} {r.text[:200]}")
    except Exception as exc:
        logger.info("Voice assistant tidak tersedia, fallback TTS lokal: %s", exc)
        tts_log(text, "voice-assistant", f"error {exc}")
    return False


def _speak_once(text: str):
    if _speak_via_assistant(text):
        return
    piper = ENV.get("PIPER_BIN", "piper")
    piper_model = ENV.get("PIPER_MODEL_ID", "")
    espeak = ENV.get("ESPEAK_BIN", "espeak-ng")
    audio_out = ENV.get("AUDIO_OUTPUT", "default")
    try:
        if shutil_which(piper) and piper_model:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
                wav_path = tf.name
            cmd = [piper, "--model", piper_model, "--output_file", wav_path, text]
            subprocess.run(cmd, check=True, capture_output=True)
            _play_audio(wav_path)
            os.unlink(wav_path)
            tts_log(text, "piper", "ok")
            set_last_spoken(text, "piper")
            return
    except Exception as e:
        logger.warning(f"Piper gagal: {e}")
    try:
        if shutil_which(espeak):
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
                wav_path = tf.name
            cmd = [espeak, "-v", "id", "-w", wav_path, text]
            subprocess.run(cmd, check=True, capture_output=True)
            _play_audio(wav_path)
            os.unlink(wav_path)
            tts_log(text, "espeak-ng", "ok")
            set_last_spoken(text, "espeak-ng")
            return
    except Exception as e:
        logger.warning(f"espeak-ng gagal: {e}")
    logger.error("Tidak ada TTS backend tersedia")
    tts_log(text, "none", "no backend available")
    set_last_spoken(text, "none")


def shutil_which(cmd):
    import shutil
    return shutil.which(cmd)


def _play_audio(path: str):
    audio_out = ENV.get("AUDIO_OUTPUT", "default")
    players = ["mpv", "aplay", "ffplay"]
    for p in players:
        if shutil_which(p):
            try:
                if p == "mpv":
                    cmd = [p, "--no-audio-display", path]
                elif p == "aplay":
                    dev = ENV.get("ALSA_DEVICE", "default")
                    cmd = [p, "-D", dev, path]
                else:
                    cmd = [p, path]
                subprocess.run(cmd, check=True, capture_output=True)
                return
            except Exception as e:
                logger.warning(f"Player {p} gagal: {e}")
    logger.error("Tidak ada audio player tersedia")


@app.post("/speak")
def speak(inp: SpeakIn):
    speak_queue(inp.text)
    return {"detail": "Suara diantrikan"}


@app.get("/tts/test")
def tts_test():
    speak_queue("Tes suara TTS Toko Arafah")
    return {"detail": "TTS tes diantrikan"}


@app.get("/tts/status")
def tts_status():
    with tts_lock:
        status = dict(last_spoken)
    return status


@app.post("/announce/item")
def announce_item(inp: AnnounceItemIn):
    price = max(0, int(inp.price))
    text = f"{inp.name.strip()}, harga {number_to_id_words(price)} rupiah"
    speak_queue(text)
    return {"text": text, "price": price}


def _cell_text(value: Any) -> str:
    if value is None:
        return ""
    try:
        import pandas as pd
        if pd.isna(value):
            return ""
    except Exception:
        pass
    text = str(value).strip()
    if text.lower() in ("nan", "none", "nat"):
        return ""
    return text


@app.post("/import/excel")
async def import_excel(
    file: UploadFile = File(...),
    update_existing: bool = True,
    allow_nonstandard: bool = False,
):
    import pandas as pd

    df = pd.read_excel(file.file, dtype=str)
    df.columns = [str(c).strip() for c in df.columns]
    barcode_col = name_col = price_col = None
    for c in df.columns:
        lc = re.sub(r"[\s_\-]+", " ", c.lower().strip())
        if lc in ("barcode", "kode", "kode barang", "barcode_id"):
            barcode_col = c
        elif lc in ("nama", "nama barang", "nama produk", "product", "name"):
            name_col = c
        elif lc in ("harga", "price", "harga jual", "harga_jual"):
            price_col = c
    if not barcode_col or not name_col:
        raise HTTPException(
            status_code=400,
            detail="Kolom barcode dan nama_barang wajib ada. Template: barcode,nama_barang,harga",
        )

    added = updated = skipped = invalid = 0
    invalid_rows = []
    conn = get_db()
    now = datetime.utcnow().isoformat()
    for idx, row in df.iterrows():
        bc = normalize_barcode(_cell_text(row[barcode_col]))
        nm = _cell_text(row[name_col])
        if not bc or not nm:
            invalid += 1
            invalid_rows.append({"row": int(idx) + 2, "barcode": bc, "reason": "barcode/nama kosong"})
            continue
        if not allow_nonstandard and not barcode_checksum_ok(bc):
            invalid += 1
            invalid_rows.append({"row": int(idx) + 2, "barcode": bc, "reason": "checksum/format barcode tidak valid"})
            continue
        price = None
        if price_col:
            raw_price = _cell_text(row[price_col])
            if raw_price:
                digits = re.sub(r"[^\d]", "", raw_price)
                if digits:
                    price = int(digits)
        existing = find_product(conn, bc)
        if existing:
            if update_existing:
                conn.execute(
                    "UPDATE products SET name = ?, price = COALESCE(?, price), updated_at = ? WHERE barcode = ?",
                    (nm, price, now, existing["barcode"]),
                )
                updated += 1
            else:
                skipped += 1
            continue
        conn.execute(
            "INSERT INTO products (barcode, name, price, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (bc, nm, price, now, now),
        )
        added += 1
    conn.commit()
    conn.close()
    return {
        "added": added,
        "updated": updated,
        "skipped": skipped,
        "invalid": invalid,
        "invalid_rows": invalid_rows[:20],
    }


@app.get("/search/suggest")
def search_suggest(
    barcode: Optional[str] = None,
    name: Optional[str] = None,
    refresh: bool = False,
):
    """Saran nama + harga untuk barang baru.

    Urutan sumber:
    1. cache lokal (kecuali ?refresh=true)
    2. Open Food/Beauty/Products Facts (nama, gratis)
    3. SerpAPI/Brave kalau API key diisi (harga)
    4. Open Prices (harga IDR, gratis)
    5. estimasi deterministik yang wajar (untuk mainan kasir)
    """
    bc = normalize_barcode(barcode)

    if bc and not refresh:
        conn = get_db()
        row = None
        for variant in barcode_variants(bc):
            row = conn.execute(
                "SELECT * FROM search_cache WHERE barcode = ?", (variant,)
            ).fetchone()
            if row:
                break
        conn.close()
        if row:
            return {
                "barcode": bc,
                "name": row["name"],
                "price_suggestions": json.loads(row["price_suggestions"] or "[]"),
                "recommended_price": row["recommended_price"],
                "source": row["source"] or "cache",
                "estimated": (row["source"] or "") == "estimasi",
                "barcode_valid": barcode_checksum_ok(bc),
                "barcode_kind": barcode_kind(bc),
                "cached": True,
            }

    suggested_name = (name or "").strip()
    source = "manual"

    facts = lookup_open_facts(bc) if bc else None
    if facts and not suggested_name:
        suggested_name = facts["name"]
        source = facts["source"]

    suggestions: List[Dict[str, str]] = []
    query = " ".join(part for part in (bc, suggested_name or name or "") if part).strip()
    if query:
        suggestions.extend(search_web_prices(query + " harga"))

    prices = []
    for item in suggestions:
        parsed = _parse_price_text(item.get("price"))
        if parsed:
            prices.append(parsed)

    if prices:
        prices.sort()
        recommended = prices[len(prices) // 2]
        source = "Pencarian web"
    else:
        recommended = lookup_open_prices(bc) if bc else None
        if recommended:
            source = "Open Prices"
        else:
            recommended = estimate_price(bc or suggested_name, suggested_name)
            source = "estimasi"

    if not any(str(item.get("source", "")).lower() == source.lower() for item in suggestions):
        suggestions.append({
            "source": source,
            "title": "Harga perkiraan, silakan ubah kalau tidak cocok" if source == "estimasi" else "Harga dari internet",
            "price": str(recommended),
        })

    if bc:
        conn = get_db()
        now = datetime.utcnow().isoformat()
        conn.execute(
            """
            INSERT OR REPLACE INTO search_cache
                (barcode, name, price_suggestions, recommended_price, source, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (bc, suggested_name or None, json.dumps(suggestions), recommended, source, now),
        )
        conn.commit()
        conn.close()

    return {
        "barcode": bc or None,
        "name": suggested_name or None,
        "price_suggestions": suggestions,
        "recommended_price": recommended,
        "source": source,
        "estimated": source == "estimasi",
        "barcode_valid": barcode_checksum_ok(bc) if bc else False,
        "barcode_kind": barcode_kind(bc),
        "cached": False,
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
