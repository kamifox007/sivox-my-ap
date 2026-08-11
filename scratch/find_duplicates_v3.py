
import collections
import re
import json

def get_duplicates():
    with open('c:/ap_nv/my_app/lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
        lines = f.readlines()

    current_lang = None
    keys_by_lang = collections.defaultdict(list)

    for i, line in enumerate(lines):
        if 'Language.en:' in line:
            current_lang = 'en'
        elif 'Language.fr:' in line:
            current_lang = 'fr'
        elif 'Language.ar:' in line:
            current_lang = 'ar'
        
        if current_lang:
            match = re.search(r"^\s*['\"](.*?)['\"]\s*:", line)
            if match:
                keys_by_lang[current_lang].append({
                    'key': match.group(1),
                    'line_index': i,
                    'content': line.strip()
                })

    result = {}
    for lang, keys in keys_by_lang.items():
        counts = collections.Counter([k['key'] for k in keys])
        duplicates = []
        for key, count in counts.items():
            if count > 1:
                key_instances = [k for k in keys if k['key'] == key]
                duplicates.append({
                    'key': key,
                    'count': count,
                    'instances': key_instances
                })
        result[lang] = duplicates

    with open('c:/ap_nv/my_app/scratch/duplicates.json', 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    get_duplicates()
