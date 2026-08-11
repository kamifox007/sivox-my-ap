
import re
from collections import Counter

def check_duplicates(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find map boundaries
    en_start = content.find("Language.en: {")
    fr_start = content.find("Language.fr: {")
    ar_start = content.find("Language.ar: {")
    end = content.rfind("},")
    
    maps = [
        ('en', en_start, fr_start),
        ('fr', fr_start, ar_start),
        ('ar', ar_start, end)
    ]

    for name, start, end in maps:
        if start == -1: continue
        segment = content[start:end]
        # Match keys like 'key': but ignore commented lines
        lines = segment.split('\n')
        keys_with_lines = []
        for i, line in enumerate(lines):
            if line.strip().startswith('//'):
                continue
            match = re.search(r"'([^']+)':", line)
            if match:
                keys_with_lines.append((match.group(1), i + 1)) # Relative to map start
        
        counts = Counter([k for k, l in keys_with_lines])
        dupes = [k for k, v in counts.items() if v > 1]
        if dupes:
            print(f"Duplicates in {name} map:")
            for dupe in dupes:
                lines_found = [l for k, l in keys_with_lines if k == dupe]
                print(f"  - '{dupe}' at relative lines {lines_found}")

check_duplicates(r'c:\ap_nv\my_app\scratch\test_dupes.dart')
