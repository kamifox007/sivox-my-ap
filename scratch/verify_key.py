
with open('c:/ap_nv/my_app/lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
    for i, line in enumerate(f):
        if 'GREETING_VISITOR' in line:
            print(f"{i+1}: {line.strip()}")
