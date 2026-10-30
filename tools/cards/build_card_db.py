#!/usr/bin/env python3
"""Genera la base de cartas de Edison Format para Garage TCG.

Se ejecuta UNA vez (o cuando se quiera refrescar) en GitHub Actions, en el
repositorio público garaje-tcg-cartas (ver LEEME.md). Solo usa la biblioteca
estándar de Python.

Qué hace:
  1. Descarga del API de YGOPRODeck las cartas legales en Edison Format
     (cardinfo.php?format=edison) con su banlist.
  2. Escribe assets/cards/edison_cards.json (empaquetado dentro de la app):
     código, nombre en inglés, tipo de carta, límite de copias y códigos de
     las ilustraciones alternativas.
  3. (Opcional) Descarga UNA vez las imágenes de cada carta (pequeña para la
     cuadrícula y la ilustración recortada para la carta principal) a una
     carpeta lista para publicar en GitHub Pages. YGOPRODeck
     pide no enlazar sus imágenes directamente: se bajan una vez y se alojan
     aparte. Descarga a ~10 peticiones/s (su límite es 20/s; pasarse = 1 h de
     bloqueo) y se salta las que ya existen, así repetir es barato.

Uso:
  python tools/cards/build_card_db.py                    # solo el JSON
  python tools/cards/build_card_db.py --site build/card_site   # JSON + imágenes

Banlist: se toma del API (campo ban_edison). Si el API no lo trae, o para
corregir alguna carta, se puede rellenar tools/cards/banlist_edison.txt con
líneas "0 Nombre", "1 Nombre" o "2 Nombre" (manda sobre el API).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://db.ygoprodeck.com/api/v7/cardinfo.php"
UA = "GarageTCG-cardbuilder/1.0 (+https://github.com/lachy97/garaje-tcg)"
ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_JSON = ROOT / "assets" / "cards" / "edison_cards.json"
OVERRIDES = pathlib.Path(__file__).resolve().parent / "banlist_edison.txt"

# Tipos que no van en un mazo.
SKIP_FRAMES = {"token", "skill"}
BAN_LIMIT = {"Banned": 0, "Forbidden": 0, "Limited": 1, "Semi-Limited": 2}


def fetch_json(url: str, tries: int = 4) -> dict:
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == tries - 1:
                raise
            print(f"  reintento ({e})", file=sys.stderr)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("unreachable")


def norm(name: str) -> str:
    """Igual que CardDb.normalize en la app (para casar el archivo de overrides)."""
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
    return "".join(out)


def load_overrides() -> dict[str, int]:
    result: dict[str, int] = {}
    if not OVERRIDES.exists():
        return result
    for raw in OVERRIDES.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        head, _, name = line.partition(" ")
        if head not in {"0", "1", "2", "3"} or not name.strip():
            sys.exit(f"Línea inválida en {OVERRIDES.name}: {raw!r}")
        result[norm(name)] = int(head)
    return result


def build_cards(raw: list[dict]) -> tuple[list[dict], bool]:
    overrides = load_overrides()
    used_overrides: set[str] = set()
    cards = []
    api_has_ban = False
    for c in raw:
        frame = c.get("frameType", "")
        if frame in SKIP_FRAMES:
            continue
        ban = (c.get("banlist_info") or {}).get("ban_edison")
        if ban:
            api_has_ban = True
        limit = BAN_LIMIT.get(ban, 3) if ban else 3
        key = norm(c["name"])
        if key in overrides:
            limit = overrides[key]
            used_overrides.add(key)
        images = [img["id"] for img in c.get("card_images", [])]
        alts = [i for i in images if i != c["id"]]
        card = {"i": c["id"], "n": c["name"], "f": frame, "l": limit}
        if alts:
            card["a"] = alts
        cards.append(card)
    for key in set(overrides) - used_overrides:
        print(f"AVISO: '{key}' de {OVERRIDES.name} no coincide con ninguna carta", file=sys.stderr)
    cards.sort(key=lambda x: x["n"].lower())
    return cards, api_has_ban


class RateLimiter:
    def __init__(self, per_second: float):
        self.gap = 1.0 / per_second
        self.lock = threading.Lock()
        self.next = time.monotonic()

    def wait(self) -> None:
        with self.lock:
            now = time.monotonic()
            if now < self.next:
                time.sleep(self.next - now)
            self.next = max(now, self.next) + self.gap


def download_images(raw: list[dict], site: pathlib.Path, rate: float) -> None:
    jobs = []
    for c in raw:
        if c.get("frameType") in SKIP_FRAMES:
            continue
        img = next((i for i in c.get("card_images", []) if i["id"] == c["id"]), None)
        if img is None and c.get("card_images"):
            img = c["card_images"][0]
        if img is None:
            continue
        jobs.append((img["image_url_small"], site / "s" / f"{c['id']}.jpg"))
        jobs.append((img["image_url_cropped"], site / "a" / f"{c['id']}.jpg"))
    (site / "s").mkdir(parents=True, exist_ok=True)
    (site / "a").mkdir(parents=True, exist_ok=True)
    pending = [(u, p) for u, p in jobs if not (p.exists() and p.stat().st_size > 0)]
    print(f"Imágenes: {len(jobs)} en total, {len(pending)} por descargar")
    limiter = RateLimiter(rate)
    failed: list[str] = []
    done = 0
    done_lock = threading.Lock()

    def get(job: tuple[str, pathlib.Path]) -> None:
        nonlocal done
        url, path = job
        for attempt in range(4):
            limiter.wait()
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=60) as r:
                    data = r.read()
                tmp = path.with_suffix(".part")
                tmp.write_bytes(data)
                tmp.replace(path)
                break
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    failed.append(url)
                    break
                if e.code == 429:
                    time.sleep(60)
                elif attempt == 3:
                    failed.append(url)
                else:
                    time.sleep(2 * (attempt + 1))
            except (urllib.error.URLError, TimeoutError):
                if attempt == 3:
                    failed.append(url)
                else:
                    time.sleep(2 * (attempt + 1))
        with done_lock:
            done += 1
            if done % 500 == 0:
                print(f"  {done}/{len(pending)}")

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(get, pending))
    if failed:
        print(f"AVISO: {len(failed)} imágenes no se pudieron bajar:", file=sys.stderr)
        for u in failed[:20]:
            print("  " + u, file=sys.stderr)


def write_site_files(site: pathlib.Path, version: str, count: int) -> None:
    site.mkdir(parents=True, exist_ok=True)
    (site / "meta.json").write_text(
        json.dumps({"version": version, "count": count}), encoding="utf-8")
    # Cloudflare Pages: las imágenes no cambian, que el teléfono las guarde.
    (site / "_headers").write_text(
        "/s/*\n  Cache-Control: public, max-age=31536000, immutable\n"
        "/a/*\n  Cache-Control: public, max-age=31536000, immutable\n",
        encoding="utf-8")
    (site / "index.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Garage TCG · cartas</title>"
        "<body style='background:#000;color:#8CF04C;font-family:sans-serif'>"
        f"<h1>Garage TCG</h1><p>Imágenes de cartas de Edison Format ({count}). "
        "Fuente: YGOPRODeck.</p><img src='a/46986414.jpg' width=240 alt=''>",
        encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", type=pathlib.Path, default=DEFAULT_JSON, help="archivo JSON de salida")
    ap.add_argument("--site", type=pathlib.Path, help="carpeta del sitio de imágenes (si se omite, no se bajan)")
    ap.add_argument("--rate", type=float, default=10.0, help="peticiones de imagen por segundo (máx. 15)")
    args = ap.parse_args()
    rate = min(args.rate, 15.0)

    print("Descargando cartas de Edison Format de YGOPRODeck…")
    raw = fetch_json(API + "?" + urllib.parse.urlencode({"format": "edison"}))["data"]
    cards, api_has_ban = build_cards(raw)
    if not api_has_ban:
        print("AVISO: el API no devolvió la banlist de Edison (ban_edison). "
              f"Todas las cartas quedan con 3 copias salvo lo que diga {OVERRIDES.name}.",
              file=sys.stderr)
    if len(cards) < 2000:
        sys.exit(f"Muy pocas cartas ({len(cards)}): algo falló, no se escribe nada.")

    version = dt.date.today().isoformat()
    out = {"version": version, "source": "YGOPRODeck format=edison", "count": len(cards), "cards": cards}
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    limited = sum(1 for c in cards if c["l"] < 3)
    print(f"OK: {len(cards)} cartas ({limited} en la banlist) → {args.json}")

    if args.site:
        download_images(raw, args.site, rate)
        write_site_files(args.site, version, len(cards))
        n = sum(1 for _ in args.site.rglob("*.jpg"))
        print(f"Sitio listo en {args.site} ({n} imágenes)")


if __name__ == "__main__":
    main()
