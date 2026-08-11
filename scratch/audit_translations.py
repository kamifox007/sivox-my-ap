
import os
import re

file_path = r'c:\ap_nv\my_app\lib\services\translation_service.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Extract EN keys
en_match = re.search(r'Language\.en: \{(.*?)\},', content, re.DOTALL)
if not en_match:
    print("EN map not found")
    exit()

en_keys = re.findall(r"'([^']+)':", en_match.group(1))
# Some use double quotes
en_keys += re.findall(r'"([^"]+)":', en_match.group(1))

# Extract AR keys
ar_match = re.search(r'Language\.ar: \{(.*?)\},', content, re.DOTALL)
if not ar_match:
    print("AR map not found")
    exit()

ar_keys = re.findall(r"'([^']+)':", ar_match.group(1))
ar_keys += re.findall(r'"([^"]+)":', ar_match.group(1))

missing_keys = [k for k in en_keys if k not in ar_keys]

print(f"Total EN keys: {len(en_keys)}")
print(f"Total AR keys: {len(ar_keys)}")
print(f"Missing AR keys: {len(missing_keys)}")
for k in missing_keys:
    print(f"- {k}")
