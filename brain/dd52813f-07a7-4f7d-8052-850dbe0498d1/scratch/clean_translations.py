import re
import os

def clean_translations(file_path):
    if not os.path.exists(file_path):
        print(f"File {file_path} not found")
        return

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    new_lines = []
    in_translations = False
    current_lang = None
    seen_keys = set()
    
    # Simple state machine
    for line in lines:
        stripped = line.strip()
        
        # Check for start of translation map
        if 'static final Map<Language, Map<String, String>> _translations' in line:
            in_translations = True
            new_lines.append(line)
            continue
            
        if not in_translations:
            new_lines.append(line)
            continue
            
        # Inside translations map
        # Check for start of a language block
        lang_match = re.search(r'Language\.(\w+)\s*:\s*\{', line)
        if lang_match:
            current_lang = lang_match.group(1)
            seen_keys = set()
            new_lines.append(line)
            continue
            
        # Check for end of a language block
        if current_lang and stripped == '},':
            current_lang = None
            new_lines.append(line)
            continue
            
        if current_lang:
            # Match a key-value pair line
            # Typical line: 'key': 'value',
            kv_match = re.search(r"^\s*['\"](.*?)['\"]\s*:", line)
            if kv_match:
                key = kv_match.group(1)
                if key in seen_keys:
                    # Duplicate found! Skip this line
                    print(f"Skipping duplicate key '{key}' in Language.{current_lang}")
                    continue
                else:
                    seen_keys.add(key)
                    new_lines.append(line)
            else:
                # Not a KV pair (could be a comment or blank line)
                new_lines.append(line)
        else:
            # Between language blocks
            new_lines.append(line)
            # Check for end of the whole map
            if stripped == '};':
                in_translations = False

    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

if __name__ == "__main__":
    clean_translations(r'c:\ap_nv\my_app\lib\services\translation_service.dart')
