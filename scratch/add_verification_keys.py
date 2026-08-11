
import re

def add_keys(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_keys = {
        'en': {
            'ACCOUNT_NOT_VERIFIED': 'Account Not Verified',
            'VERIFY_NOW': 'Verify Now',
            'VERIFICATION_SENT': 'Verification email sent!',
        },
        'fr': {
            'ACCOUNT_NOT_VERIFIED': 'Compte non vérifié',
            'VERIFY_NOW': 'Vérifier maintenant',
            'VERIFICATION_SENT': 'E-mail de vérification envoyé !',
        },
        'ar': {
            'ACCOUNT_NOT_VERIFIED': 'الحساب غير موثق',
            'VERIFY_NOW': 'وثق الآن',
            'VERIFICATION_SENT': 'تم إرسال رابط التوثيق!',
        }
    }

    langs = ['en', 'fr', 'ar']
    for lang in langs:
        pattern = f'Language\.{lang}: {{'
        start = content.find(pattern)
        if start == -1: continue
        
        # Find end of map
        brace_count = 0
        end = -1
        for j in range(start, len(content)):
            if content[j] == '{': brace_count += 1
            elif content[j] == '}': brace_count -= 1
            if brace_count == 0:
                end = j
                break
        
        if end == -1: continue
        
        # Insert before the closing brace
        keys_str = ""
        for k, v in new_keys[lang].items():
            keys_str += f"      '{k}': '{v}',\n"
        
        content = content[:end] + keys_str + content[end:]

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

if __name__ == "__main__":
    add_keys('c:/ap_nv/my_app/lib/services/translation_service.dart')
