import re

with open('LinoriaLite.lua', 'r') as f:
    content = f.read()

# We will regex replace the function signatures.
# AddToggle
content = re.sub(r'function Obj:AddToggle\(name, default, callback\)', r'function Obj:AddToggle(name, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)
# AddSlider
content = re.sub(r'function Obj:AddSlider\(name, min, max, default, callback\)', r'function Obj:AddSlider(name, min, max, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)
# AddDropdown
content = re.sub(r'function Obj:AddDropdown\(name, options, default, callback\)', r'function Obj:AddDropdown(name, options, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)
# AddMultiDropdown
content = re.sub(r'function Obj:AddMultiDropdown\(name, options, default, callback\)', r'function Obj:AddMultiDropdown(name, options, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)
# AddKeybind
content = re.sub(r'function Obj:AddKeybind\(name, default, callback\)', r'function Obj:AddKeybind(name, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)
# AddColorPicker
content = re.sub(r'function Obj:AddColorPicker\(name, default, callback\)', r'function Obj:AddColorPicker(name, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)
# AddInput
content = re.sub(r'function Obj:AddInput\(name, default, callback\)', r'function Obj:AddInput(name, default, callback, idx)\n        idx = idx or name:gsub(" ", "")', content)

# Now we need to inject the Library.Options[idx] = ... before the return.
# This is trickier because the return statements look like:
# return { SetValue = ... }
# Or for AddToggle: return ToggleObj.
# It's better to just manually edit them since there are only 7 functions.

with open('LinoriaLite.lua', 'w') as f:
    f.write(content)
print("Done modifying signatures!")
