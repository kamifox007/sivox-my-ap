
import re

with open('c:/ap_nv/my_app/lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    stripped = line.strip()
    if not stripped: continue
    if stripped.startswith('//'): continue
    if stripped in ['{', '}', '},', '};', '];']: continue
    if 'import' in line or 'class' in line or 'enum' in line or 'static' in line or 'extension' in line or 'return' in line or 'for' in line: continue
    
    # Key match
    if re.search(r"^\s*['\"](.*?)['\"]\s*:", line):
        continue
    
    # Language match
    if 'Language.' in line:
        continue
        
    # If we are here, it's a line that isn't a key, nor a standard structural line.
    # It might be the second line of a multi-line value.
    # We should check if the PREVIOUS line was a key line.
    
    prev_line = lines[i-1] if i > 0 else ""
    if re.search(r":\s*$", prev_line.strip()):
        # It's a multi-line value continuation, that's fine.
        continue
        
    print(f"Stray line at {i+1}: {stripped}")
