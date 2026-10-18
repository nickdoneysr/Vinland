"""Build data/art_manifest.json and placeholder PNGs from Vinland_Art_Asset_List.xlsx.

Usage: python3 tools/make_manifest.py path/to/Vinland_Art_Asset_List.xlsx
Every asset gets a placeholder at art_placeholder/<same path>. Real art saved at
art/<path> always wins at runtime (see scripts/autoload/art.gd).
"""
import json, re, sys, pathlib
import openpyxl
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
TINT = {'STY': (120, 110, 90), 'SKY': (120, 150, 170), 'CLD': (170, 180, 185), 'SEA': (47, 74, 87), 'CST': (70, 90, 70),
        'SHP': (110, 85, 60), 'WFX': (150, 160, 170), 'NAV': (138, 109, 78), 'FSH': (50, 90, 100), 'HNT': (100, 110, 70),
        'FOR': (90, 110, 60), 'BLD': (130, 100, 70), 'BAL': (60, 70, 80), 'CMP': (110, 130, 80), 'ANI': (140, 110, 80),
        'CHR': (150, 120, 100), 'MKT': (120, 100, 90), 'MAP': (150, 125, 90), 'LOD': (100, 90, 80), 'UIK': (160, 135, 100),
        'HUD': (150, 125, 95), 'ICN': (140, 120, 90), 'EVT': (90, 80, 100), 'END': (60, 60, 80), 'MNU': (40, 60, 75),
        'VFX': (200, 200, 200), 'MKG': (80, 80, 80)}

def parse_size(s):
    nums = re.findall(r'(\d[\d,]*)\s*[×x]\s*(\d[\d,]*)', s)
    if not nums:
        return [256, 256]
    w, h = nums[0]
    return [int(w.replace(',', '')), int(h.replace(',', ''))]

def main(xlsx):
    wb = openpyxl.load_workbook(xlsx, data_only=True)
    ws = wb['Asset List']
    hdr = [c.value for c in ws[4]]
    idx = {h: i for i, h in enumerate(hdr)}
    manifest = {}
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 28)
        small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 18)
    except OSError:
        font = small = ImageFont.load_default()
    for row in ws.iter_rows(min_row=5, values_only=True):
        aid = row[idx['ID']]
        if not aid or '-' not in str(aid):
            continue
        path = str(row[idx['File path']]).split(' ')[0]
        size = parse_size(str(row[idx['Export size (px)']]))
        if '1080 safe' in str(row[idx['Export size (px)']]):
            size = [1920, 1200]
        entry = dict(path=path, size=size, name=row[idx['Asset']], type=row[idx['Type']],
                     frames=row[idx['Frames / states']], phase=row[idx['Phase needed']], priority=row[idx['Priority']])
        manifest[aid] = entry
        if not path.startswith('res://art/'):
            continue
        rel = path.replace('res://art/', '').rstrip('/')
        if rel.endswith('/') or not rel.endswith('.png'):
            rel = rel.rstrip('/') + '.png'
            entry['placeholder_only_file'] = True
        out = ROOT / 'art_placeholder' / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        entry['placeholder'] = 'res://art_placeholder/' + rel
        if out.exists():
            continue
        w, h = size
        t = TINT.get(aid[:3], (100, 100, 100))
        img = Image.new('RGBA', (w, h), t + (200,))
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, w - 1, h - 1], outline=(255, 255, 255, 230), width=max(1, min(w, h) // 60))
        if min(w, h) >= 48:
            d.text((max(4, w // 40), max(4, h // 40)), aid, fill=(255, 255, 255, 255), font=font if min(w, h) >= 128 else small)
            if min(w, h) >= 128:
                d.text((max(4, w // 40), max(4, h // 40) + 34), str(row[idx['Asset']])[:60], fill=(255, 255, 255, 220), font=small)
        img.save(out)
    (ROOT / 'data').mkdir(exist_ok=True)
    (ROOT / 'data' / 'art_manifest.json').write_text(json.dumps(manifest, indent=1, ensure_ascii=False))
    print(len(manifest), 'assets in manifest')

if __name__ == '__main__':
    main(sys.argv[1])
