
import collections

with open('c:/ap_nv/my_app/lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

current_lang = None
keys_by_lang = collections.defaultdict(list)

for line in lines:
    if 'Language.en:' in line:
        current_lang = 'en'
    elif 'Language.fr:' in line:
        current_lang = 'fr'
    elif 'Language.ar:' in line:
        current_lang = 'ar'
    
    if current_lang:
        # Match 'KEY': or "KEY":
        import re
        match = re.search(r"^\s*['\"](.*?)['\"]\s*:", line)
        if match:
            keys_by_lang[current_lang].append((match.group(1), line.strip()))

for lang, keys in keys_by_lang.items():
    print(f"--- Duplicates in {lang} ---")
    counts = collections.Counter([k[0] for k in keys])
    for key, count in counts.items():
        if count > 1:
            print(f"Key '{key}' found {count} times:")
            # Find which lines
            for k, original_line in keys:
                if k == key:
                    print(f"  {original_line}")
