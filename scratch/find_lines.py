
with open('c:/ap_nv/my_app/lib/services/translation_service.dart', 'r', encoding='utf-8') as f:
    for i, line in enumerate(f):
        if 'Language.en:' in line:
            print(f"en: {i+1}")
        if 'Language.fr:' in line:
            print(f"fr: {i+1}")
        if 'Language.ar:' in line:
            print(f"ar: {i+1}")
