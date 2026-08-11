import re
import os

file_path = r'c:\ap_nv\my_app\lib\services\translation_service.dart'
if not os.path.exists(file_path):
    print("File not found")
    exit(1)

content = open(file_path, 'r', encoding='utf-8').read()

def get_map(lang):
    # Match everything between 'Language.xx: {' and '},'
    pattern = rf'Language\.{lang}: \{{(.*?)\}},(\s+Language\.(ar|fr|en)| \}};)'
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        # Try finding it at the end
        pattern_end = rf'Language\.{lang}: \{{(.*?)\}},(\s+\}})'
        match = re.search(pattern_end, content, re.DOTALL)
    
    return match.group(1) if match else ''

for l in ['en', 'fr', 'ar']:
    section = get_map(l)
    if not section:
        print(f"Section {l} NOT FOUND")
        continue

    # Extract keys
    keys = re.findall(r"['\"](\w+)['\"]:", section)
    counts = {}
    for k in keys:
        counts[k] = counts.get(k, 0) + 1
    
    dups = [k for k, v in counts.items() if v > 1]
    print(f"\n--- {l.upper()} Duplicates ({len(dups)}) ---")
    for d in dups:
        print(f"Key: {d} (Count: {counts[d]})")
