import os
import re

main_dir = 'rtl/MainBand'
workspace = '.'

# Gather the new bases
new_bases = []
for root, dirs, files in os.walk(main_dir):
    for f in files:
        if f.startswith('unit_') and f.endswith('.sv'):
            new_bases.append(f[:-3])

print(f"Found {len(new_bases)} new module bases.")

def replace_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    new_content = content
    changed = False
    
    for new_base in new_bases:
        old_base_lower = new_base[5:] # remove 'unit_'
        
        # We need to replace occurrences of the old base (case insensitive) with new_base.
        # But ONLY if it's a module declaration or instantiation.
        # Let's write regex for module declaration: `module <OldName>`
        # and instantiation: `<OldName> <inst_name> (` or `<OldName> #(`
        
        # Replace module declaration
        # (?i) is case insensitive
        # module \bOldName\b
        pattern_mod = re.compile(r'\bmodule\s+' + re.escape(old_base_lower) + r'\b', re.IGNORECASE)
        new_content, n_mod = pattern_mod.subn(r'module ' + new_base, new_content)
        
        # Replace module instantiation (e.g. OldName inst_name (...) or OldName #(...) )
        # Regex: \bOldName\b(?=\s+\w+|\s+#)
        pattern_inst = re.compile(r'\b' + re.escape(old_base_lower) + r'\b(?=\s+\w+|\s+#\s*\()', re.IGNORECASE)
        new_content, n_inst = pattern_inst.subn(new_base, new_content)
        
        # Replace in listfiles (which are .f files) - just replace the filename
        if filepath.endswith('.f'):
            # replace filename with case insensitive
            pattern_f = re.compile(r'(?i)\b' + re.escape(old_base_lower) + r'\.sv\b')
            new_content, n_f = pattern_f.subn(new_base + '.sv', new_content)
            # also replace if it's just the old base
            # pattern_f2 = re.compile(r'(?i)\b' + re.escape(old_base_lower) + r'\b')
            # new_content, n_f2 = pattern_f2.subn(new_base, new_content)
        else:
            n_f = 0
            
        if n_mod > 0 or n_inst > 0 or n_f > 0:
            changed = True

    if changed:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"Updated {filepath}")

for root, dirs, files in os.walk(workspace):
    # skip .git etc
    if '.git' in root or '.gemini' in root:
        continue
    for f in files:
        if f.endswith('.sv') or f.endswith('.f') or f.endswith('.v'):
            filepath = os.path.join(root, f)
            replace_in_file(filepath)

print("Done!")
