import os

lib_path = 'lib'
keep_file = 'main.dart'

# Files in the root of lib/ to delete if not main.dart
files = [f for f in os.listdir(lib_path) if os.path.isfile(os.path.join(lib_path, f))]

for f in files:
    if f != keep_file:
        path = os.path.join(lib_path, f)
        os.remove(path)
        print(f"Deleted legacy root file: {f}")
