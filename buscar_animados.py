#!/usr/bin/env python3
import json, urllib.request, urllib.parse, sys, time

OUTPUT = "/home/dandi/super-ffmpeg-stream/animados"
NEED = 141
FOUND = []
PAGE = 1

def fetch(q, page, rows=200):
    url = ("https://archive.org/advancedsearch.php?q=" +
           urllib.parse.quote(q) +
           f"&fl[]=identifier&fl[]=title&rows={rows}&page={page}&output=json")
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"  Error: {e}")
        return None

q = ("subject:(cartoon OR animated OR animation) AND "
     "date:[1900 TO 1970] AND format:(MPEG4)")

data = fetch(q, 1, 1)
if not data:
    sys.exit(1)
total = data.get("response", {}).get("numFound", 0)
print(f"  Total disponibles: {total}")

while len(FOUND) < min(NEED, total) and (PAGE - 1) * 200 < total:
    print(f"  Pagina {PAGE}...")
    data = fetch(q, PAGE, 200)
    if not data:
        break
    docs = data.get("response", {}).get("docs", [])
    if not docs:
        break
    for doc in docs:
        i = doc.get("identifier", "")
        t = doc.get("title", "")
        if i and t:
            FOUND.append(f"{t} | https://archive.org/download/{i}/{i}.mp4")
    print(f"  Acumulados: {len(FOUND)}")
    PAGE += 1

print(f"\n  Escribiendo {min(len(FOUND), NEED)} URLs a {OUTPUT}...")
with open(OUTPUT, "w") as f:
    f.write("# Animados - Dibujos animados clasicos (public domain, 70s o anterior)\n")
    f.write("# Fuentes: archive.org (PD Cartoons, animacion clasica)\n")
    f.write("# Formato: titulo | URL\n")
    for url in FOUND[:NEED]:
        f.write(url + "\n")

count = sum(1 for _ in open(OUTPUT) if "|" in _ and not _.startswith("#"))
print(f"  Hecho: {count} URLs escritas.")
