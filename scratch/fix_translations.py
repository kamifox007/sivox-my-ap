
import re
import collections

def cleanup_translations(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Split the content into parts: prefix, en_map, fr_map, ar_map, suffix
    en_start = content.find('Language.en: {')
    fr_start = content.find('Language.fr: {', en_start)
    ar_start = content.find('Language.ar: {', fr_start)
    
    # Function to find the end of a map starting at its opening brace
    def find_map_end(text, start_pos):
        brace_count = 0
        in_map = False
        for i in range(start_pos, len(text)):
            if text[i] == '{':
                brace_count += 1
                in_map = True
            elif text[i] == '}':
                brace_count -= 1
            if in_map and brace_count == 0:
                return i + 1
        return -1

    en_end = find_map_end(content, en_start)
    fr_end = find_map_end(content, fr_start)
    ar_end = find_map_end(content, ar_start)

    if en_end == -1 or fr_end == -1 or ar_end == -1:
        print("Could not find map boundaries correctly.")
        return

    prefix = content[:en_start]
    en_part = content[en_start:en_end]
    fr_part = content[fr_start:fr_end]
    ar_part = content[ar_start:ar_end]
    suffix = content[ar_end:]

    # Function to remove duplicates in a part while keeping the LAST occurrence
    def deduplicate_part(part, label):
        lines = part.split('\n')
        new_lines = []
        key_to_last_index = {}
        
        # First pass: find last index of each key
        for i, line in enumerate(lines):
            match = re.search(r"^\s*['\"](.*?)['\"]\s*:", line)
            if match:
                key = match.group(1)
                key_to_last_index[key] = i
        
        # Second pass: only keep the last index or non-key lines
        for i, line in enumerate(lines):
            match = re.search(r"^\s*['\"](.*?)['\"]\s*:", line)
            if match:
                key = match.group(1)
                if key_to_last_index[key] == i:
                    new_lines.append(line)
                else:
                    # Keep commented out lines if they were duplicates
                    if line.strip().startswith('//'):
                         new_lines.append(line)
                    # Otherwise skip
            else:
                new_lines.append(line)
        
        return '\n'.join(new_lines)

    # Note: the parts include the Language.xx: { and closing }, which is fine.
    new_en = deduplicate_part(en_part, 'en')
    new_fr = deduplicate_part(fr_part, 'fr')
    new_ar = deduplicate_part(ar_part, 'ar')

    # Reconstruct the whole file
    # We need to handle the spacers between parts.
    # The current prefix ends at en_start.
    # The space between en_end and fr_start might contain comments or whitespace.
    
    gap_en_fr = content[en_end:fr_start]
    gap_fr_ar = content[fr_end:ar_start]
    
    new_content = prefix + new_en + gap_en_fr + new_fr + gap_fr_ar + new_ar + suffix
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Cleanup complete.")

if __name__ == "__main__":
    cleanup_translations('c:/ap_nv/my_app/lib/services/translation_service.dart')
