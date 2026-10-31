import os
import json
import sqlite3
import subprocess
import tempfile
import logging
from pathlib import Path
from typing import List, Optional, Dict, Any
from datetime import datetime
from threading import Lock

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
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
            created_at TEXT
        )
    """)
    conn.commit()
    conn.close()


init_db()


class ProductIn(BaseModel):
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
    row = conn.execute("SELECT * FROM products WHERE barcode = ?", (barcode,)).fetchone()
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
def create_product(p: ProductIn, barcode: str = Form(None)):
    conn = get_db()
    now = datetime.utcnow().isoformat()
    try:
        conn.execute(
            "INSERT INTO products (barcode, name, price, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (barcode or p.name, p.name, p.price, now, now),
        )
        conn.commit()
    except sqlite3.IntegrityError:
        conn.close()
        raise HTTPException(status_code=409, detail="Barcode sudah ada")
    row = conn.execute("SELECT * FROM products WHERE barcode = ?", (barcode or p.name,)).fetchone()
    conn.close()
    return dict(row)


@app.put("/products/{barcode}", response_model=ProductOut)
def update_product(barcode: str, p: ProductIn):
    conn = get_db()
    row = conn.execute("SELECT * FROM products WHERE barcode = ?", (barcode,)).fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    now = datetime.utcnow().isoformat()
    name = p.name if p.name is not None else row["name"]
    price = p.price if p.price is not None else row["price"]
    conn.execute(
        "UPDATE products SET name = ?, price = ?, updated_at = ? WHERE barcode = ?",
        (name, price, now, barcode),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM products WHERE barcode = ?", (barcode,)).fetchone()
    conn.close()
    return dict(row)


@app.delete("/products/{barcode}")
def delete_product(barcode: str):
    conn = get_db()
    cur = conn.execute("DELETE FROM products WHERE barcode = ?", (barcode,))
    conn.commit()
    conn.close()
    if cur.rowcount == 0:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    return {"detail": "Produk dihapus"}


@app.post("/checkout")
def checkout(inp: CheckoutIn):
    if not inp.items:
        raise HTTPException(status_code=400, detail="Keranjang kosong")
    conn = get_db()
    total = 0
    now = datetime.utcnow().isoformat()
    cur = conn.execute("INSERT INTO transactions (total, created_at) VALUES (?, ?)", (0, now))
    tx_id = cur.lastrowid
    for item in inp.items:
        row = conn.execute("SELECT * FROM products WHERE barcode = ?", (item.barcode,)).fetchone()
        if not row:
            conn.rollback()
            conn.close()
            raise HTTPException(status_code=404, detail=f"Produk {item.barcode} tidak ditemukan")
        price = row["price"] or 0
        subtotal = price * item.qty
        total += subtotal
        conn.execute(
            "INSERT INTO transaction_items (transaction_id, barcode, name, price, qty) VALUES (?, ?, ?, ?, ?)",
            (tx_id, item.barcode, row["name"], price, item.qty),
        )
    conn.execute("UPDATE transactions SET total = ? WHERE id = ?", (total, tx_id))
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
    import threading
    threading.Thread(target=_speak, daemon=True).start()


def _speak_once(text: str):
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
            return
    except Exception as e:
        logger.warning(f"espeak-ng gagal: {e}")
    logger.error("Tidak ada TTS backend tersedia")


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


@app.post("/import/excel")
async def import_excel(file: UploadFile = File(...)):
    import pandas as pd
    df = pd.read_excel(file.file, dtype={"barcode": str})
    df.columns = [str(c).strip() for c in df.columns]
    barcode_col = None
    name_col = None
    price_col = None
    for c in df.columns:
        lc = c.lower().strip()
        if lc in ("barcode", "kode", "kode barang"):
            barcode_col = c
        if lc in ("nama", "nama barang", "nama_produk", "product"):
            name_col = c
        if lc in ("harga", "price", "harga_jual"):
            price_col = c
    if not barcode_col or not name_col:
        raise HTTPException(status_code=400, detail="Kolom barcode dan nama_barang wajib ada")
    added = 0
    skipped = 0
    invalid = 0
    conn = get_db()
    for _, row in df.iterrows():
        bc = str(row[barcode_col]).strip() if pd.notna(row[barcode_col]) else ""
        nm = str(row[name_col]).strip() if pd.notna(row[name_col]) else ""
        if not bc or not nm:
            invalid += 1
            continue
        price = None
        if price_col and pd.notna(row[price_col]):
            try:
                price = int(float(row[price_col]))
            except Exception:
                pass
        existing = conn.execute("SELECT 1 FROM products WHERE barcode = ?", (bc,)).fetchone()
        if existing:
            skipped += 1
            continue
        now = datetime.utcnow().isoformat()
        conn.execute(
            "INSERT INTO products (barcode, name, price, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (bc, nm, price, now, now),
        )
        added += 1
    conn.commit()
    conn.close()
    return {"added": added, "skipped": skipped, "invalid": invalid}


@app.get("/search/suggest")
def search_suggest(barcode: Optional[str] = None, name: Optional[str] = None):
    env = load_env()
    cache_barcode = barcode
    if cache_barcode:
        conn = get_db()
        row = conn.execute("SELECT * FROM search_cache WHERE barcode = ?", (cache_barcode,)).fetchone()
        conn.close()
        if row:
            return {
                "barcode": barcode,
                "name": row["name"],
                "price_suggestions": json.loads(row["price_suggestions"] or "[]"),
                "cached": True,
            }

    suggestions = []
    suggested_name = name or ""
    provider = env.get("SEARCH_PROVIDER", "none").lower()

    if provider == "serpapi" and env.get("SERPAPI_KEY"):
        try:
            import requests
            q = f"{barcode or ''} {name or ''} harga".strip()
            url = "https://serpapi.com/search.json"
            params = {"q": q, "api_key": env["SERPAPI_KEY"], "engine": "google", "gl": "id", "hl": "id"}
            r = requests.get(url, params=params, timeout=15)
            data = r.json()
            for res in data.get("shopping_results", [])[:5]:
                suggestions.append({
                    "source": res.get("source", "Tidak diketahui"),
                    "title": res.get("title", ""),
                    "price": res.get("price", ""),
                })
            if not suggested_name:
                for res in data.get("organic_results", [])[:3]:
                    if res.get("title"):
                        suggested_name = res["title"]
                        break
        except Exception as e:
            logger.warning(f"SerpAPI gagal: {e}")
    elif provider == "brave" and env.get("BRAVE_KEY"):
        try:
            import requests
            q = f"{barcode or ''} {name or ''} harga".strip()
            url = "https://api.search.brave.com/res/v1/web/search"
            headers = {"X-Subscription-Token": env["BRAVE_KEY"]}
            params = {"q": q, "count": 5}
            r = requests.get(url, headers=headers, params=params, timeout=15)
            data = r.json()
            for res in data.get("web", {}).get("results", [])[:5]:
                suggestions.append({
                    "source": res.get("source", "Tidak diketahui"),
                    "title": res.get("title", ""),
                    "price": "",
                })
        except Exception as e:
            logger.warning(f"Brave gagal: {e}")
    else:
        suggestions.append({
            "source": "Manual",
            "title": "Cari harga di Google/Tokopedia/Shopee",
            "price": "",
        })

    prices = []
    for s in suggestions:
        import re
        m = re.findall(r"[\d\.]+", str(s.get("price", "")))
        if m:
            try:
                prices.append(int(m[0].replace(".", "")))
            except Exception:
                pass
    recommended = None
    if prices:
        prices.sort()
        recommended = prices[len(prices) // 2]

    if cache_barcode:
        conn = get_db()
        now = datetime.utcnow().isoformat()
        conn.execute(
            "INSERT OR REPLACE INTO search_cache (barcode, name, price_suggestions, created_at) VALUES (?, ?, ?, ?)",
            (cache_barcode, suggested_name, json.dumps(suggestions), now),
        )
        conn.commit()
        conn.close()

    return {
        "barcode": barcode,
        "name": suggested_name,
        "price_suggestions": suggestions,
        "recommended_price": recommended,
        "cached": False,
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
