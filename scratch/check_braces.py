
with open('c:/ap_nv/my_app/lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

brace_count = 0
for i, char in enumerate(content):
    if char == '{':
        brace_count += 1
    elif char == '}':
        brace_count -= 1
    
    if brace_count < 0:
        print(f"Brace mismatch at index {i}: negative count")
        break

print(f"Final brace count: {brace_count}")
