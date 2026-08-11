
import re
from collections import Counter

def check_duplicates(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    current_lang = None
    maps = {'en': [], 'fr': [], 'ar': []}
    
    for i, line in enumerate(lines):
        line_num = i + 1
        if 'Language.en:' in line:
            current_lang = 'en'
        elif 'Language.fr:' in line:
            current_lang = 'fr'
        elif 'Language.ar:' in line:
            current_lang = 'ar'
        
        # Match only active lines (no // at start or with some space)
        if line.strip().startswith('//'):
            continue
            
        match = re.search(r"^\s*'([^']+)'\s*:", line)
        if match and current_lang:
            key = match.group(1)
            maps[current_lang].append((key, line_num))

    for lang, keys_with_lines in maps.items():
        keys = [k for k, l in keys_with_lines]
        counts = Counter(keys)
        dupes = [k for k, v in counts.items() if v > 1]
        if dupes:
            for dupe in dupes:
                lines_found = [l for k, l in keys_with_lines if k == dupe]
                print(f"Duplicate key '{dupe}' in {lang} map at lines {lines_found}")
        else:
            print(f"No duplicates in {lang} map.")

check_duplicates(r'c:\ap_nv\my_app\lib\services\translation_service.dart')
