
import re

def fix_with_blocks(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the language maps
    # We'll do it language by language to avoid mixing them.
    langs = ['Language.en', 'Language.fr', 'Language.ar']
    parts = []
    last_end = 0
    
    for i, lang in enumerate(langs):
        start = content.find(lang + ': {', last_end)
        if start == -1: continue
        
        # Keep everything between last_end and start
        parts.append(('text', content[last_end:start]))
        
        # Find map end
        brace_count = 0
        end = -1
        for j in range(start, len(content)):
            if content[j] == '{': brace_count += 1
            elif content[j] == '}': brace_count -= 1
            if brace_count == 0:
                end = j + 1
                break
        
        if end == -1: break
        
        map_content = content[start:end]
        parts.append(('map', map_content, lang))
        last_end = end
    
    parts.append(('text', content[last_end:]))
    
    new_final_content = ""
    for part in parts:
        if part[0] == 'text':
            new_final_content += part[1]
        else:
            map_text = part[1]
            lang_label = part[2]
            
            # Extract entries
            lines = map_text.split('\n')
            header = lines[0] # Language.xx: {
            footer = lines[-1] # },
            
            entries = collections.OrderedDict()
            current_key = None
            current_block = []
            
            for line in lines[1:-1]:
                stripped = line.strip()
                if not stripped:
                    if current_key: current_block.append(line)
                    else: pass # ignore empty lines before first key
                    continue
                
                # Check if this line starts a new key
                match = re.search(r"^\s*['\"](.*?)['\"]\s*:", line)
                if match:
                    # Save previous entry if any
                    if current_key:
                        entries[current_key] = current_block
                    
                    current_key = match.group(1)
                    current_block = [line]
                else:
                    if current_key:
                        current_block.append(line)
                    else:
                        # Comments or something before first key
                        pass 
            
            # Last entry
            if current_key:
                entries[current_key] = current_block
            
            # Reconstruct map
            new_map_text = header + '\n'
            for key, block in entries.items():
                new_map_text += '\n'.join(block) + '\n'
            new_map_text += footer
            new_final_content += new_map_text
            
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_final_content)

import collections
if __name__ == "__main__":
    fix_with_blocks('c:/ap_nv/my_app/lib/services/translation_service.dart')
