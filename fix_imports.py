import os

root_dir = 'lib'
old_import = 'package:my_app/app_theme.dart'
new_import = 'package:my_app/theme/app_theme.dart'

for root, dirs, files in os.walk(root_dir):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            if old_import in content:
                new_content = content.replace(old_import, new_import)
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Fixed: {path}")
