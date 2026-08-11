
import os
import re

file_path = r'c:\ap_nv\my_app\lib\services\translation_service.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

def extract_keys(lang_code):
    match = re.search(fr'Language\.{lang_code}: \{(.*?)\},', content, re.DOTALL)
    if not match:
        return []
    keys = re.findall(r"'([^']+)':", match.group(1))
    keys += re.findall(r'"([^"]+)":', match.group(1))
    return set(keys)

en_keys = extract_keys('en')
ar_keys = extract_keys('ar')
fr_keys = extract_keys('fr')

# We want ALL keys from ANY map to be in ALL maps.
all_keys = en_keys.union(ar_keys).union(fr_keys)

missing_in_en = all_keys - en_keys
missing_in_ar = all_keys - ar_keys
missing_in_fr = all_keys - fr_keys

print(f"Total Unique Keys: {len(all_keys)}")
print(f"Missing in EN: {len(missing_in_en)}")
print(f"Missing in AR: {len(missing_in_ar)}")
print(f"Missing in FR: {len(missing_in_fr)}")

print("\n--- Missing in FR ---")
for k in sorted(missing_in_fr):
    print(k)

print("\n--- Missing in EN ---")
for k in sorted(missing_in_en):
    print(k)

print("\n--- Missing in AR ---")
for k in sorted(missing_in_ar):
    print(k)
