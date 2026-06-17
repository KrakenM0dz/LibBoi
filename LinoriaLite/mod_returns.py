import re

with open('LinoriaLite.lua', 'r') as f:
    content = f.read()

# 1. Toggle
content = content.replace('''        return ToggleObj
    end

    function Obj:AddButton''', '''        ToggleObj.Type = "Toggle"
        ToggleObj.Value = state
        ToggleObj.Save = function(self) return self.Value end
        ToggleObj.Load = function(self, val) self.SetValue(val) end
        Library.Options[idx] = ToggleObj
        return ToggleObj
    end

    function Obj:AddButton''')

# 2. Input
content = content.replace('''        Input.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                callback(Input.Text)
            end
        end)

        return {
            SetValue = function(newText)
                Input.Text = newText
                callback(newText)
            end
        }''', '''        Input.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                Library.Options[idx].Value = Input.Text
                callback(Input.Text)
            end
        end)

        local obj = {
            Type = "Input",
            Value = default,
            SetValue = function(newText)
                Input.Text = newText
                Library.Options[idx].Value = newText
                callback(newText)
            end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self.SetValue(val) end
        }
        Library.Options[idx] = obj
        return obj''')

# 3. Slider
content = content.replace('''        UpdateSlider(default, true)
        return { 
            SetValue = function(newVal) UpdateSlider(newVal, false) end,''', '''        UpdateSlider(default, true)
        local obj = { 
            Type = "Slider",
            Value = default,
            SetValue = function(newVal) UpdateSlider(newVal, false) end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self.SetValue(val) end,''')

content = content.replace('''                SliderOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
    end
    
    function Obj:AddDropdown''', '''                SliderOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end
    
    function Obj:AddDropdown''')

# Slider Value Update inside UpdateSlider
content = content.replace('''            ValueLabel.Text = tostring(value) .. "/" .. tostring(max)
            callback(value)
        end''', '''            ValueLabel.Text = tostring(value) .. "/" .. tostring(max)
            if Library.Options[idx] then Library.Options[idx].Value = value end
            callback(value)
        end''')

# 4. Dropdown
content = content.replace('''        return {
            SetValue = function(newVal)
                selected = newVal''', '''        local obj = {
            Type = "Dropdown",
            Value = selected,
            Save = function(self) return self.Value end,
            Load = function(self, val) self.SetValue(val) end,
            SetValue = function(newVal)
                selected = newVal
                if Library.Options[idx] then Library.Options[idx].Value = newVal end''')

content = content.replace('''                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
    end

    function Obj:AddMultiDropdown''', '''                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddMultiDropdown''')
    
content = content.replace('''                    SelectedLabel.Text = tostring(opt)
                    callback(opt)''', '''                    SelectedLabel.Text = tostring(opt)
                    if Library.Options[idx] then Library.Options[idx].Value = opt end
                    callback(opt)''')

# 5. MultiDropdown
content = content.replace('''        return {
            SetValue = function(newTable)''', '''        local obj = {
            Type = "MultiDropdown",
            Value = selected,
            Save = function(self)
                local res = {}
                for k, v in pairs(self.Value) do if v then table.insert(res, k) end end
                return res
            end,
            Load = function(self, val) self.SetValue(val) end,
            SetValue = function(newTable)''')

content = content.replace('''                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
    end

    function Obj:AddKeybind''', '''                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddKeybind''')

# 6. Keybind
content = content.replace('''        return {
            SetValue = function(k)''', '''        local obj = {
            Type = "Keybind",
            Value = key.Name,
            Save = function(self) return self.Value end,
            Load = function(self, val)
                if type(val) == "string" and Enum.KeyCode[val] then
                    self.SetValue(Enum.KeyCode[val])
                end
            end,
            SetValue = function(k)
                if Library.Options[idx] then Library.Options[idx].Value = k.Name end''')

content = content.replace('''                ValueLabel.Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]"
            end
        }
    end

    function Obj:AddColorPicker''', '''                ValueLabel.Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]"
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddColorPicker''')
content = content.replace('''                key = input.KeyCode
                ValueLabel.Text = "[" .. key.Name .. "]"
                ValueLabel.TextColor3 = Library.Theme.TextMuted
                callback(key)''', '''                key = input.KeyCode
                ValueLabel.Text = "[" .. key.Name .. "]"
                ValueLabel.TextColor3 = Library.Theme.TextMuted
                if Library.Options[idx] then Library.Options[idx].Value = key.Name end
                callback(key)''')


# 7. ColorPicker
content = content.replace('''        local function SetColor(c, invoke)
            local finalColor = Color3.fromHSV(c.H, c.S, c.V)''', '''        local function SetColor(c, invoke)
            local finalColor = Color3.fromHSV(c.H, c.S, c.V)
            if Library.Options[idx] then Library.Options[idx].Value = finalColor end''')

content = content.replace('''        return {
            SetValue = function(c)''', '''        local obj = {
            Type = "ColorPicker",
            Value = default,
            Save = function(self) return {R = self.Value.R, G = self.Value.G, B = self.Value.B} end,
            Load = function(self, val)
                if type(val) == "table" and val.R then
                    self.SetValue(Color3.new(val.R, val.G, val.B))
                end
            end,
            SetValue = function(c)''')

content = content.replace('''                SetColor({H = h, S = s, V = v}, false)
            end
        }
    end

    function Obj:CreateGroupBox''', '''                SetColor({H = h, S = s, V = v}, false)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:CreateGroupBox''')

with open('LinoriaLite.lua', 'w') as f:
    f.write(content)
print("Done!")
