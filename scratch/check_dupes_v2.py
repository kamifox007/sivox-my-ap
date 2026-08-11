
import re

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
        
        match = re.search(r"^\s*'([^']+)'\s*:", line)
        if match and current_lang:
            key = match.group(1)
            maps[current_lang].append((key, line_num))

    for lang, keys in maps.items():
        seen = {}
        for key, num in keys:
            if key in seen:
                print(f"Duplicate key '{key}' in {lang} map at lines {seen[key]} and {num}")
            seen[key] = num

check_duplicates(r'c:\ap_nv\my_app\lib\services\translation_service.dart')
