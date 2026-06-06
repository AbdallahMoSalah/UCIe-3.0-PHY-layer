import os
import re

main_dir = 'rtl/MainBand'

for root, dirs, files in os.walk(main_dir):
    for f in files:
        if f.endswith('.sv'):
            old_base = f[:-3]
            new_base = old_base.lower()
            if not new_base.startswith('unit_'):
                new_base = 'unit_' + new_base
            
            old_path = os.path.join(root, f)
            new_path = os.path.join(root, new_base + '.sv')
            
            # Read content
            with open(old_path, 'r') as file:
                content = file.read()
            
            # Replace old module name with new module name
            # We assume the module name inside the file is exactly old_base (case-insensitive maybe? No, let's use regex with exact old_base first, if not found try case-insensitive).
            # Actually, SystemVerilog is case-sensitive, so it should match exact old_base.
            # But let's replace exact old_base.
            content = re.sub(r'\b' + re.escape(old_base) + r'\b', new_base, content)
            
            # Write back
            with open(old_path, 'w') as file:
                file.write(content)
            
            # Rename file
            if old_path != new_path:
                os.rename(old_path, new_path)
                print(f"Renamed {old_path} -> {new_path}")

print("Done!")
