import re

with open('LinoriaLite.lua', 'r') as f:
    content = f.read()

lines = content.split('\n')
new_lines = []

in_create = False
current_theme_map = {}
count = 0

for i, line in enumerate(lines):
    if 'Create(' in line and '{' in line:
        in_create = True
        current_theme_map = {}
        new_lines.append(line)
        continue
        
    if in_create:
        match = re.search(r'([A-Za-z0-9]+)\s*=\s*Library\.Theme\.([A-Za-z0-9]+)', line)
        if match:
            prop = match.group(1)
            themeKey = match.group(2)
            if prop != 'Font':
                current_theme_map[prop] = themeKey
        
        if re.search(r'^\s*}\)', line):
            in_create = False
            if current_theme_map:
                count += 1
                map_str = 'ThemeMap = {'
                for p, t in current_theme_map.items():
                    map_str += f'{p} = "{t}", '
                map_str = map_str.strip(', ') + '}'
                
                if new_lines and not new_lines[-1].strip().endswith(',') and not new_lines[-1].strip().endswith('{'):
                    new_lines[-1] = new_lines[-1] + ','
                    
                indent = len(line) - len(line.lstrip()) + 4
                new_lines.append(' ' * indent + map_str)
        new_lines.append(line)
    else:
        new_lines.append(line)

print("Modified", count, "creates")
with open('LinoriaLite.lua', 'w') as f:
    f.write('\n'.join(new_lines))
