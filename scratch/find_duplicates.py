import re

with open('lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

ar_start = -1
for i, line in enumerate(lines):
    if 'Language.ar: {' in line:
        ar_start = i
        break

if ar_start != -1:
    keys = {}
    for i in range(ar_start + 1, len(lines)):
        line = lines[i].strip()
        if line == '},': # End of map
            break
        match = re.search(r"'([^']+)':", line)
        if match:
            key = match.group(1)
            if key in keys:
                print(f"Duplicate key '{key}' at line {i+1} (previously at line {keys[key]})")
            else:
                keys[key] = i + 1
