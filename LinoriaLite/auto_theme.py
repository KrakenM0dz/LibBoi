import re

def process_file():
    with open("LinoriaLite.lua", "r") as f:
        content = f.read()
        
    # We want to replace Create("ClassName", { ... }) with Create("ClassName", { ..., ThemeMap = { ... } })
    
    # We will iterate line by line.
    lines = content.split('\n')
    new_lines = []
    
    in_create = False
    current_theme_map = {}
    create_end_line = -1
    
    for i, line in enumerate(lines):
        if 'Create(' in line and '{' in line:
            in_create = True
            current_theme_map = {}
            new_lines.append(line)
            continue
            
        if in_create:
            # check for properties
            match = re.search(r'([A-Za-z0-9]+)\s*=\s*Library\.Theme\.([A-Za-z0-9]+)', line)
            if match:
                prop = match.group(1)
                themeKey = match.group(2)
                if prop not in ['Font']: # Font is an Enum, not a color we update dynamically easily, but we could.
                    current_theme_map[prop] = themeKey
            
            # check for end of create
            if re.search(r'^\s*}\)', line):
                in_create = False
                if current_theme_map:
                    # insert ThemeMap before this line
                    map_str = "ThemeMap = {"
                    for p, t in current_theme_map.items():
                        map_str += f'{p} = "{t}", '
                    map_str = map_str.strip(', ') + "}"
                    
                    # we need to ensure the previous line has a comma!
                    if new_lines and not new_lines[-1].strip().endswith(',') and not new_lines[-1].strip().endswith('{'):
                        new_lines[-1] = new_lines[-1] + ','
                        
                    # find indentation
                    indent = len(line) - len(line.lstrip())
                    new_lines.append(' ' * indent + map_str)
            new_lines.append(line)
        else:
            new_lines.append(line)

    with open("LinoriaLite.lua", "w") as f:
        f.write('\n'.join(new_lines))
        
if __name__ == "__main__":
    process_file()
