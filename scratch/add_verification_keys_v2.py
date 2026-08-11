
def add_keys_robust(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

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

    current_lang = None
    new_lines = []
    
    for i, line in enumerate(lines):
        if 'Language.en:' in line: current_lang = 'en'
        elif 'Language.fr:' in line: current_lang = 'fr'
        elif 'Language.ar:' in line: current_lang = 'ar'
        
        # If we reach the end of a map, insert the keys
        if current_lang and '},' in line and (i+1 < len(lines) and ('Language.' in lines[i+1] or '};' in lines[i+1])):
            # This is likely the end of the language map
            for k, v in new_keys[current_lang].items():
                new_lines.append(f"      '{k}': '{v}',\n")
            current_lang = None # reset to avoid double insertion if nested
        
        new_lines.append(line)

    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

if __name__ == "__main__":
    add_keys_robust('c:/ap_nv/my_app/lib/services/translation_service.dart')
