
import re
from collections import Counter

def check_duplicates(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find English map
    en_match = re.search(r"Language\.en:\s*\{", content)
    fr_match = re.search(r"Language\.fr:\s*\{", content)
    ar_match = re.search(r"Language\.ar:\s*\{", content)
    
    maps = [
        ('en', en_match.start() if en_match else None, fr_match.start() if fr_match else None),
        ('fr', fr_match.start() if fr_match else None, ar_match.start() if ar_match else None),
        ('ar', ar_match.start() if ar_match else None, content.find('};', ar_match.start() if ar_match else 0))
    ]

    for name, start, end in maps:
        if start is None: continue
        segment = content[start:end]
        keys = re.findall(r"'([^']+)':", segment)
        counts = Counter(keys)
        dupes = [k for k, v in counts.items() if v > 1]
        if dupes:
            print(f"Duplicates in {name} map: {dupes}")
        else:
            print(f"No duplicates in {name} map.")

check_duplicates(r'c:\ap_nv\my_app\lib\services\translation_service.dart')
