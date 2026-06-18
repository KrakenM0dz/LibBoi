local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer

local Library = {}
Library.Connections = {}
Library.Options = {}
Library.ThemeObjects = {}

function Library:Unload()
    for _, connection in ipairs(Library.Connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(Library.Connections)
    table.clear(Library.ThemeObjects)
    table.clear(Library.Options)
    if Library.ScreenGui then
        Library.ScreenGui:Destroy()
    end
end

Library.Theme = {
    BackgroundColor = Color3.fromRGB(15, 15, 15),
    MainColor = Color3.fromRGB(20, 20, 20),
    GroupBoxColor = Color3.fromRGB(15, 15, 15),
    OutlineColor = Color3.fromRGB(0, 0, 0),
    InlineColor = Color3.fromRGB(50, 50, 50),
    AccentColor = Color3.fromRGB(0, 255, 255),
    Font = Enum.Font.Code,
    TextColor = Color3.fromRGB(255, 255, 255),
    TextMuted = Color3.fromRGB(150, 150, 150),
}

function Library:UpdateTheme(themeVar, newColor)
    Library.Theme[themeVar] = newColor
    for obj, props in pairs(Library.ThemeObjects) do
        for propName, themeKey in pairs(props) do
            if themeKey == themeVar then
                pcall(function() obj[propName] = newColor end)
            end
        end
    end
    for _, obj in pairs(Library.Options) do
        if type(obj.UpdateColors) == "function" then
            obj:UpdateColors()
        end
    end
end

local function Create(className, properties)
    local instance = Instance.new(className)
    properties = properties or {}
    local themeMap = properties.ThemeMap
    properties.ThemeMap = nil
    for k, v in pairs(properties) do
        instance[k] = v
    end
    if themeMap then
        Library.ThemeObjects[instance] = themeMap
    end
    return instance
end

local function GetTextBounds(text, font, size)
    return TextService:GetTextSize(text, size, font, Vector2.new(9999, 9999))
end

local function MakeDraggable(dragHandle, window)
    local dragging, dragInput, dragStart, startPos

    local function update(input)
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
end

local function BindElementMethods(Obj, ElementContainer, WindowObj)
    local ScreenGui = WindowObj.ScreenGui
    function Obj:AddLabel(text)
        local LabelFrame = Create("Frame", {
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })
        local Label = Create("TextLabel", {
            Parent = LabelFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = text,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })
        return { SetText = function(newText) Label.Text = newText end }
    end

    function Obj:AddDivider()
        local DivContainer = Create("Frame", {
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 6)
        })
        local DivOutline = Create("Frame", {
            Parent = DivContainer,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, 0, 0, 1),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local DivInline = Create("Frame", {
            Parent = DivContainer,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 0, 0.5, 1),
            Size = UDim2.new(1, 0, 0, 1),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
    end

    function Obj:AddToggle(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        local state = default or false
        callback = callback or function() end

        local ToggleFrame = Create("Frame", {
            Name = name.."_Toggle",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })

        local CheckOutline = Create("Frame", {
            Parent = ToggleFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, 10, 0, 10),
            Position = UDim2.new(0, 0, 0.5, -5),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local CheckInline = Create("Frame", {
            Parent = CheckOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local CheckFill = Create("Frame", {
            Parent = CheckInline,
            BackgroundColor3 = state and Library.Theme.AccentColor or Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0
        })

        local Label = Create("TextLabel", {
            Name = "Label",
            Parent = ToggleFrame,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 18, 0, 0),
            Size = UDim2.new(1, -18, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = state and Library.Theme.TextColor or Library.Theme.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left
        })

        local Button = Create("TextButton", {
            Parent = ToggleFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = ""
        })

        local function SetState(newState)
            state = newState
            local targetBg = state and Library.Theme.AccentColor or Library.Theme.GroupBoxColor
            local targetText = state and Library.Theme.TextColor or Library.Theme.TextMuted
            TweenService:Create(CheckFill, TweenInfo.new(0.15), {BackgroundColor3 = targetBg}):Play()
            TweenService:Create(Label, TweenInfo.new(0.15), {TextColor3 = targetText}):Play()
            callback(state)
        end

        Button.MouseButton1Click:Connect(function() SetState(not state) end)
        SetState(state)
        
        local ToggleObj = { 
            SetValue = function(newState) SetState(newState) end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                Button.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                Button.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }

        function ToggleObj:AddKeybind(defaultKey)
            local key = defaultKey or Enum.KeyCode.Unknown
            local binding = false

            local ValueLabel = Create("TextLabel", {
                Parent = ToggleFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(1, -50, 0, 0),
                Size = UDim2.new(0, 50, 1, 0),
                Font = Library.Theme.Font,
                Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]",
                TextColor3 = Library.Theme.TextMuted,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = 5,
ThemeMap = {TextColor3 = "TextMuted"}
            })
            
            local BindBtn = Create("TextButton", {
                Parent = ValueLabel,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                ZIndex = 6
            })
            
            BindBtn.MouseButton1Click:Connect(function()
                binding = true
                ValueLabel.Text = "[...]"
                ValueLabel.TextColor3 = Library.Theme.AccentColor
            end)

            local keyConn = UserInputService.InputBegan:Connect(function(input, processed)
                if binding and input.UserInputType == Enum.UserInputType.Keyboard then
                    if input.KeyCode == Enum.KeyCode.Escape then
                        key = Enum.KeyCode.Unknown
                    else
                        key = input.KeyCode
                    end
                    binding = false
                    ValueLabel.Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]"
                    ValueLabel.TextColor3 = Library.Theme.TextMuted
                elseif not binding and not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key and key ~= Enum.KeyCode.Unknown then
                    SetState(not state)
                end
            end)
            table.insert(Library.Connections, keyConn)
            
            return {
                SetKey = function(newKey)
                    key = newKey
                    ValueLabel.Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]"
                end
            }
        end

        ToggleObj.Type = "Toggle"
        ToggleObj.Value = state
        ToggleObj.UpdateColors = function()
            local targetBg = state and Library.Theme.AccentColor or Library.Theme.GroupBoxColor
            local targetText = state and Library.Theme.TextColor or Library.Theme.TextMuted
            CheckFill.BackgroundColor3 = targetBg
            Label.TextColor3 = targetText
        end
        ToggleObj.Save = function(self) return self.Value end
        ToggleObj.Load = function(self, val) self.SetValue(val) end
        Library.Options[idx] = ToggleObj
        return ToggleObj
    end

    function Obj:AddButton(name, callback)
        callback = callback or function() end
        
        local ButtonFrame = Create("Frame", {
            Name = name.."_Button",
            Parent = ElementContainer,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BtnInline = Create("Frame", {
            Parent = ButtonFrame,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BtnBg = Create("Frame", {
            Parent = BtnInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local Label = Create("TextLabel", {
            Parent = BtnBg,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            ZIndex = 2,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local Button = Create("TextButton", {
            Parent = BtnBg,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 3
        })
        
        Create("UIGradient", {
            Parent = BtnBg,
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7))
            })
        })

        Button.MouseButton1Down:Connect(function() TweenService:Create(BtnBg, TweenInfo.new(0.1), {BackgroundColor3 = Library.Theme.InlineColor}):Play() end)
        Button.MouseButton1Up:Connect(function() TweenService:Create(BtnBg, TweenInfo.new(0.1), {BackgroundColor3 = Library.Theme.GroupBoxColor}):Play() end)
        Button.MouseLeave:Connect(function() TweenService:Create(BtnBg, TweenInfo.new(0.1), {BackgroundColor3 = Library.Theme.GroupBoxColor}):Play() end)
        Button.MouseButton1Click:Connect(callback)
        
        return {
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                Button.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                Button.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
    end

    function Obj:AddInput(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        default = default or ""
        callback = callback or function() end

        local InputFrame = Create("Frame", {
            Name = name.."_Input",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36)
        })

        local Label = Create("TextLabel", {
            Parent = InputFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = InputFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BoxBg = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local TextBox = Create("TextBox", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 6, 0, 0),
            Size = UDim2.new(1, -12, 1, 0),
            Font = Library.Theme.Font,
            Text = tostring(default),
            TextColor3 = Library.Theme.TextColor,
            PlaceholderText = "...",
            PlaceholderColor3 = Library.Theme.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
ThemeMap = {TextColor3 = "TextColor", PlaceholderColor3 = "TextMuted"}
        })

        local obj = {
            Type = "Input",
            Value = default,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
                TextBox.TextColor3 = Library.Theme.TextColor
                TextBox.PlaceholderColor3 = Library.Theme.TextMuted
            end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self.SetValue(val) end,
            SetValue = function(text) 
                TextBox.Text = tostring(text)
                if Library.Options[idx] then Library.Options[idx].Value = TextBox.Text end
                callback(TextBox.Text) 
            end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        TextBox.FocusLost:Connect(function()
            if Library.Options[idx] then Library.Options[idx].Value = TextBox.Text end
            callback(TextBox.Text)
        end)
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddSlider(name, min, max, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        min = min or 0
        max = max or 100
        default = default or min
        callback = callback or function() end
        
        local value = default

        local SliderFrame = Create("Frame", {
            Name = name.."_Slider",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 28)
        })

        local Label = Create("TextLabel", {
            Parent = SliderFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local SliderOutline = Create("Frame", {
            Parent = SliderFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 14),
            Size = UDim2.new(1, 0, 0, 14),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local SliderInline = Create("Frame", {
            Parent = SliderOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local SliderBg = Create("Frame", {
            Parent = SliderInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local SliderFill = Create("Frame", {
            Parent = SliderBg,
            BackgroundColor3 = Library.Theme.AccentColor,
            Size = UDim2.new(0, 0, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 2,
ThemeMap = {BackgroundColor3 = "AccentColor"}
        })
        
        Create("UIGradient", {
            Parent = SliderFill,
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7))
            })
        })

        local ValueLabel = Create("TextLabel", {
            Parent = SliderBg,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = tostring(value) .. "/" .. tostring(max),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            ZIndex = 4,
ThemeMap = {TextColor3 = "TextColor"}
        })
        Create("UIStroke", {
            Parent = ValueLabel,
            Color = Library.Theme.OutlineColor,
            Thickness = 1,
ThemeMap = {Color = "OutlineColor"}
        })

        local function UpdateSlider(val, instant)
            value = math.clamp(val, min, max)
            value = math.floor(value)
            local percent = (value - min) / (max - min)
            if instant then
                SliderFill.Size = UDim2.new(percent, 0, 1, 0)
            else
                TweenService:Create(SliderFill, TweenInfo.new(0.05), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
            end
            ValueLabel.Text = tostring(value) .. "/" .. tostring(max)
            if Library.Options[idx] then Library.Options[idx].Value = value end
            callback(value)
        end

        local dragging = false
        
        local function move(input)
            local pos = input.Position.X - SliderBg.AbsolutePosition.X
            local percent = math.clamp(pos / SliderBg.AbsoluteSize.X, 0, 1)
            local newValue = min + (max - min) * percent
            UpdateSlider(newValue, false)
        end

        SliderOutline.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                move(input)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                move(input)
            end
        end)

        UpdateSlider(default, true)
        local obj = { 
            Type = "Slider",
            Value = default,
            UpdateColors = function()
                SliderFill.BackgroundColor3 = Library.Theme.AccentColor
                ValueLabel.TextColor3 = Library.Theme.TextColor
                Label.TextColor3 = Library.Theme.TextColor
            end,
            SetValue = function(newVal) UpdateSlider(newVal, false) end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self.SetValue(val) end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                SliderOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                SliderOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end
    
    function Obj:AddDropdown(name, options, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        options = options or {}
        default = default or options[1]
        callback = callback or function() end
        
        local selected = default
        local open = false
        
        local DropdownFrame = Create("Frame", {
            Name = name.."_Dropdown",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36)
        })

        local Label = Create("TextLabel", {
            Parent = DropdownFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = DropdownFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BoxBg = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })
        
        local SelectedLabel = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 6, 0, 0),
            Size = UDim2.new(1, -26, 1, 0),
            Font = Library.Theme.Font,
            Text = tostring(selected),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })
        
        local Indicator = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -20, 0, 0),
            Size = UDim2.new(0, 20, 1, 0),
            Font = Library.Theme.Font,
            Text = "▼",
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 10,
ThemeMap = {TextColor3 = "TextMuted"}
        })
        
        local ToggleBtn = Create("TextButton", {
            Parent = BoxOutline,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 5
        })
        
        local OptsOutline = Create("Frame", {
            Parent = ScreenGui,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, 0),
            Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21),
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 5000,
            ClipsDescendants = true,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local OptsInline = Create("Frame", {
            Parent = OptsOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local OptsBg = Create("Frame", {
            Parent = OptsInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })
        
        local OptionsLayout = Create("UIListLayout", {
            Parent = OptsBg,
            SortOrder = Enum.SortOrder.LayoutOrder
        })
        
        local function UpdateOptions()
            local targetSize = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, open and (OptionsLayout.AbsoluteContentSize.Y + 4) or 0)
            if open then OptsOutline.Visible = true end
            
            local tween = TweenService:Create(OptsOutline, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})
            tween:Play()
            
            if not open then
                tween.Completed:Connect(function()
                    if not open then OptsOutline.Visible = false end
                end)
            end
            
            OptsOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21)
        end
        
        BoxOutline:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
            if open then UpdateOptions() end
        end)
        BoxOutline:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if open then UpdateOptions() end
        end)
        
        local optionButtons = {}
        
        local function SetOptions(newOptions)
            options = newOptions
            for _, btn in pairs(optionButtons) do btn:Destroy() end
            table.clear(optionButtons)
            
            for i, opt in ipairs(options) do
                local OptBtn = Create("TextButton", {
                    Parent = OptsBg,
                    BackgroundColor3 = Library.Theme.GroupBoxColor,
                    Size = UDim2.new(1, 0, 0, 18),
                    BorderSizePixel = 0,
                    Font = Library.Theme.Font,
                    Text = "  " .. tostring(opt),
                    TextColor3 = (opt == selected) and Library.Theme.AccentColor or Library.Theme.TextColor,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 5005,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
                })
                
                OptBtn.MouseButton1Click:Connect(function()
                    selected = opt
                    SelectedLabel.Text = tostring(opt)
                    if Library.Options[idx] then Library.Options[idx].Value = opt end
                    callback(opt)
                    for _, b in pairs(optionButtons) do
                        b.TextColor3 = Library.Theme.TextColor
                    end
                    OptBtn.TextColor3 = Library.Theme.AccentColor
                    open = false
                    OptsOutline.Visible = false
                    Indicator.Text = "▼"
                end)
                
                OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.InlineColor end)
                OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.GroupBoxColor end)
                table.insert(optionButtons, OptBtn)
            end
            UpdateOptions()
        end
        
        SetOptions(options)
        
        ToggleBtn.MouseButton1Click:Connect(function()
            open = not open
            OptsOutline.Visible = open
            Indicator.Text = open and "▲" or "▼"
            if open then UpdateOptions() end
        end)
        
        UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if open then
                    local mPos = input.Position
                    local cPos, cSize = OptsOutline.AbsolutePosition, OptsOutline.AbsoluteSize
                    local bPos, bSize = BoxOutline.AbsolutePosition, BoxOutline.AbsoluteSize
                    
                    local inOptions = (mPos.X >= cPos.X and mPos.X <= cPos.X + cSize.X and mPos.Y >= cPos.Y and mPos.Y <= cPos.Y + cSize.Y)
                    local inBox = (mPos.X >= bPos.X and mPos.X <= bPos.X + bSize.X and mPos.Y >= bPos.Y and mPos.Y <= bPos.Y + bSize.Y)
                    
                    if not inOptions and not inBox then
                        open = false
                        OptsOutline.Visible = false
                        Indicator.Text = "▼"
                    end
                end
            end
        end)

        local obj = {
            Type = "Dropdown",
            Value = selected,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
                SelectedLabel.TextColor3 = Library.Theme.TextMuted
            end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self.SetValue(val) end,
            SetValue = function(newVal)
                selected = newVal
                if Library.Options[idx] then Library.Options[idx].Value = newVal end
                SelectedLabel.Text = tostring(newVal)
                for _, b in pairs(optionButtons) do
                    b.TextColor3 = (string.sub(b.Text, 3) == tostring(newVal)) and Library.Theme.AccentColor or Library.Theme.TextColor
                end
                callback(newVal)
            end,
            RefreshOptions = function(newOptions) SetOptions(newOptions) end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddMultiDropdown(name, options, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        options = options or {}
        default = default or {}
        callback = callback or function() end
        
        local selected = {}
        for _, v in ipairs(default) do selected[v] = true end
        local open = false
        
        local DropdownFrame = Create("Frame", {
            Name = name.."_MultiDropdown",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36)
        })

        local Label = Create("TextLabel", {
            Parent = DropdownFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = DropdownFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BoxBg = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })
        
        local function GetSelectedString()
            local str = ""
            for _, opt in ipairs(options) do
                if selected[opt] then
                    str = str .. tostring(opt) .. ", "
                end
            end
            if str == "" then return "None" end
            return string.sub(str, 1, -3)
        end

        local SelectedLabel = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 6, 0, 0),
            Size = UDim2.new(1, -26, 1, 0),
            Font = Library.Theme.Font,
            Text = GetSelectedString(),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
ThemeMap = {TextColor3 = "TextColor"}
        })
        
        local Indicator = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -20, 0, 0),
            Size = UDim2.new(0, 20, 1, 0),
            Font = Library.Theme.Font,
            Text = "▼",
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 10,
ThemeMap = {TextColor3 = "TextMuted"}
        })
        
        local ToggleBtn = Create("TextButton", {
            Parent = BoxOutline,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 5
        })
        
        local OptsOutline = Create("Frame", {
            Parent = ScreenGui,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, 0),
            Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21),
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 5000,
            ClipsDescendants = true,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local OptsInline = Create("Frame", {
            Parent = OptsOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local OptsBg = Create("Frame", {
            Parent = OptsInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })
        
        local OptionsLayout = Create("UIListLayout", {
            Parent = OptsBg,
            SortOrder = Enum.SortOrder.LayoutOrder
        })
        
        local function UpdateOptions()
            local targetSize = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, open and (OptionsLayout.AbsoluteContentSize.Y + 4) or 0)
            if open then OptsOutline.Visible = true end
            
            local tween = TweenService:Create(OptsOutline, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})
            tween:Play()
            
            if not open then
                tween.Completed:Connect(function()
                    if not open then OptsOutline.Visible = false end
                end)
            end
            
            OptsOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21)
        end
        
        BoxOutline:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
            if open then UpdateOptions() end
        end)
        BoxOutline:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if open then UpdateOptions() end
        end)
        
        local optionButtons = {}
        
        local function SetOptions(newOptions)
            options = newOptions
            for _, btn in pairs(optionButtons) do btn:Destroy() end
            table.clear(optionButtons)
            
            for i, opt in ipairs(options) do
                local isSelected = selected[opt] or false
                local OptBtn = Create("TextButton", {
                    Parent = OptsBg,
                    BackgroundColor3 = Library.Theme.GroupBoxColor,
                    Size = UDim2.new(1, 0, 0, 18),
                    BorderSizePixel = 0,
                    Font = Library.Theme.Font,
                    Text = "  " .. (isSelected and "[X] " or "[ ] ") .. tostring(opt),
                    TextColor3 = isSelected and Library.Theme.AccentColor or Library.Theme.TextColor,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 5005,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
                })
                
                OptBtn.MouseButton1Click:Connect(function()
                    selected[opt] = not selected[opt]
                    local newSelected = selected[opt]
                    OptBtn.Text = "  " .. (newSelected and "[X] " or "[ ] ") .. tostring(opt)
                    OptBtn.TextColor3 = newSelected and Library.Theme.AccentColor or Library.Theme.TextColor
                    SelectedLabel.Text = GetSelectedString()
                    
                    local activeList = {}
                    for _, o in ipairs(options) do
                        if selected[o] then table.insert(activeList, o) end
                    end
                    callback(activeList)
                end)
                
                OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.InlineColor end)
                OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.GroupBoxColor end)
                table.insert(optionButtons, OptBtn)
            end
            UpdateOptions()
        end
        
        SetOptions(options)
        
        ToggleBtn.MouseButton1Click:Connect(function()
            open = not open
            OptsOutline.Visible = open
            Indicator.Text = open and "▲" or "▼"
            if open then UpdateOptions() end
        end)
        
        local mConn = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if open then
                    local mPos = input.Position
                    local cPos, cSize = OptsOutline.AbsolutePosition, OptsOutline.AbsoluteSize
                    local bPos, bSize = BoxOutline.AbsolutePosition, BoxOutline.AbsoluteSize
                    
                    local inOptions = (mPos.X >= cPos.X and mPos.X <= cPos.X + cSize.X and mPos.Y >= cPos.Y and mPos.Y <= cPos.Y + cSize.Y)
                    local inBox = (mPos.X >= bPos.X and mPos.X <= bPos.X + bSize.X and mPos.Y >= bPos.Y and mPos.Y <= bPos.Y + bSize.Y)
                    
                    if not inOptions and not inBox then
                        open = false
                        OptsOutline.Visible = false
                        Indicator.Text = "▼"
                    end
                end
            end
        end)
        table.insert(Library.Connections, mConn)

        local obj = {
            Type = "MultiDropdown",
            Value = selected,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
                SelectedLabel.TextColor3 = Library.Theme.TextMuted
            end,
            Save = function(self)
                local res = {}
                for k, v in pairs(self.Value) do if v then table.insert(res, k) end end
                return res
            end,
            Load = function(self, val) self.SetValue(val) end,
            SetValue = function(newTable)
                selected = {}
                for _, v in ipairs(newTable) do selected[v] = true end
                SetOptions(options)
                SelectedLabel.Text = GetSelectedString()
                callback(newTable)
            end,
            RefreshOptions = function(newOptions) SetOptions(newOptions) end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddKeybind(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        default = default or Enum.KeyCode.Unknown
        callback = callback or function() end
        
        local key = default
        local binding = false

        local KeybindFrame = Create("Frame", {
            Name = name.."_Keybind",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })

        local Label = Create("TextLabel", {
            Parent = KeybindFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -50, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local ValueLabel = Create("TextLabel", {
            Parent = KeybindFrame,
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -50, 0, 0),
            Size = UDim2.new(0, 50, 1, 0),
            Font = Library.Theme.Font,
            Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]",
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
ThemeMap = {TextColor3 = "TextMuted"}
        })

        local Button = Create("TextButton", {
            Parent = KeybindFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = ""
        })

        Button.MouseButton1Click:Connect(function()
            binding = true
            ValueLabel.Text = "[...]"
            ValueLabel.TextColor3 = Library.Theme.AccentColor
        end)

        UserInputService.InputBegan:Connect(function(input, processed)
            if binding and input.UserInputType == Enum.UserInputType.Keyboard then
                binding = false
                key = input.KeyCode
                ValueLabel.Text = "[" .. key.Name .. "]"
                ValueLabel.TextColor3 = Library.Theme.TextMuted
                if Library.Options[idx] then Library.Options[idx].Value = key.Name end
                callback(key)
            elseif not processed and input.KeyCode == key and key ~= Enum.KeyCode.Unknown then
                callback(key)
            end
        end)

        local obj = {
            Type = "Keybind",
            Value = key.Name,
            Save = function(self) return self.Value end,
            Load = function(self, val)
                if type(val) == "string" and Enum.KeyCode[val] then
                    self.SetValue(Enum.KeyCode[val])
                end
            end,
            SetValue = function(k)
                if Library.Options[idx] then Library.Options[idx].Value = k.Name end
                key = k
                ValueLabel.Text = "[" .. (key.Name == "Unknown" and "None" or key.Name) .. "]"
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddColorPicker(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        default = default or Color3.new(1, 1, 1)
        callback = callback or function() end
        
        local h, s, v = Color3.toHSV(default)
        local open = false

        local PickerFrame = Create("Frame", {
            Name = name.."_ColorPicker",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })

        local Label = Create("TextLabel", {
            Parent = PickerFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -30, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = PickerFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(1, -20, 0, 2),
            Size = UDim2.new(0, 20, 0, 10),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local ColorDisplay = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = default,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0
        })

        local ToggleBtn = Create("TextButton", {
            Parent = PickerFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 5
        })

        local FlyoutOutline = Create("Frame", {
            Parent = ScreenGui,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, 160, 0, 175),
            Visible = false,
            ZIndex = 6000,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local FlyoutInline = Create("Frame", {
            Parent = FlyoutOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 6000,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local FlyoutBg = Create("Frame", {
            Parent = FlyoutInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 6000,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        -- SV Map
        local SVOutline = Create("Frame", {
            Parent = FlyoutBg,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 5, 0, 5),
            Size = UDim2.new(1, -10, 0, 140),
            BorderSizePixel = 0,
            ZIndex = 6001,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local SVBg = Create("Frame", {
            Parent = SVOutline,
            BackgroundColor3 = Color3.fromHSV(h, 1, 1),
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 16
        })
        local SVWhite = Create("Frame", {
            Parent = SVBg,
            BackgroundColor3 = Color3.new(1,1,1),
            Size = UDim2.new(1, 0, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 6002
        })
        Create("UIGradient", {
            Parent = SVWhite,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1)
            })
        })
        local SVBlack = Create("Frame", {
            Parent = SVBg,
            BackgroundColor3 = Color3.new(0,0,0),
            Size = UDim2.new(1, 0, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 6003
        })
        Create("UIGradient", {
            Parent = SVBlack,
            Rotation = -90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0)
            })
        })

        local SVCursor = Create("Frame", {
            Parent = SVBg,
            BackgroundColor3 = Color3.new(1,1,1),
            Size = UDim2.new(0, 4, 0, 4),
            Position = UDim2.new(s, -2, 1 - v, -2),
            BorderSizePixel = 1,
            BorderColor3 = Color3.new(0,0,0),
            ZIndex = 6004
        })

        -- Hue Map
        local HueOutline = Create("Frame", {
            Parent = FlyoutBg,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 5, 0, 150),
            Size = UDim2.new(1, -10, 0, 15),
            BorderSizePixel = 0,
            ZIndex = 6001,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local HueBg = Create("Frame", {
            Parent = HueOutline,
            BackgroundColor3 = Color3.new(1,1,1),
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 16
        })
        Create("UIGradient", {
            Parent = HueBg,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
                ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
                ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
                ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
                ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
                ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1))
            })
        })
        local HueCursor = Create("Frame", {
            Parent = HueBg,
            BackgroundColor3 = Color3.new(1,1,1),
            Size = UDim2.new(0, 2, 1, 0),
            Position = UDim2.new(h, -1, 0, 0),
            BorderSizePixel = 1,
            BorderColor3 = Color3.new(0,0,0),
            ZIndex = 6002
        })

        local function UpdateColor()
            local c = Color3.fromHSV(h, s, v)
            ColorDisplay.BackgroundColor3 = c
            SVBg.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            SVCursor.Position = UDim2.new(math.clamp(s, 0, 1), -2, math.clamp(1 - v, 0, 1), -2)
            HueCursor.Position = UDim2.new(math.clamp(h, 0, 1), -1, 0, 0)
            if Library.Options[idx] then Library.Options[idx].Value = c end
            callback(c)
        end

        local draggingSV = false
        local draggingHue = false

        local function UpdateSV(input)
            local pos = input.Position
            local bounds = SVBg.AbsoluteSize
            local offset = SVBg.AbsolutePosition
            s = math.clamp((pos.X - offset.X) / bounds.X, 0, 1)
            v = 1 - math.clamp((pos.Y - offset.Y) / bounds.Y, 0, 1)
            UpdateColor()
        end

        local function UpdateH(input)
            local pos = input.Position
            local bounds = HueBg.AbsoluteSize
            local offset = HueBg.AbsolutePosition
            h = math.clamp((pos.X - offset.X) / bounds.X, 0, 1)
            UpdateColor()
        end

        SVOutline.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingSV = true
                UpdateSV(input)
            end
        end)
        HueOutline.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingHue = true
                UpdateH(input)
            end
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingSV = false
                draggingHue = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                if draggingSV then UpdateSV(input) end
                if draggingHue then UpdateH(input) end
            end
        end)

        ToggleBtn.MouseButton1Click:Connect(function()
            open = not open
            FlyoutOutline.Visible = open
            if open then
                FlyoutOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X + 25, 0, BoxOutline.AbsolutePosition.Y)
            end
        end)
        
        PickerFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
            if open then
                FlyoutOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X + 25, 0, BoxOutline.AbsolutePosition.Y)
            end
        end)
        
        UserInputService.InputBegan:Connect(function(input)
            if open and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                local m = input.Position
                local fPos, fSize = FlyoutOutline.AbsolutePosition, FlyoutOutline.AbsoluteSize
                local bPos, bSize = BoxOutline.AbsolutePosition, BoxOutline.AbsoluteSize
                
                local inFlyout = m.X >= fPos.X and m.X <= fPos.X + fSize.X and m.Y >= fPos.Y and m.Y <= fPos.Y + fSize.Y
                local inBox = m.X >= bPos.X and m.X <= bPos.X + bSize.X and m.Y >= bPos.Y and m.Y <= bPos.Y + bSize.Y
                
                if not inFlyout and not inBox then
                    open = false
                    FlyoutOutline.Visible = false
                end
            end
        end)
        
        UpdateColor()
        
        local obj = {
            Type = "ColorPicker",
            Value = default,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
            end,
            Save = function(self) return {R = self.Value.R, G = self.Value.G, B = self.Value.B} end,
            Load = function(self, val)
                if type(val) == "table" and val.R then
                    self.SetValue(Color3.new(val.R, val.G, val.B))
                end
            end,
            SetValue = function(c)
                h, s, v = Color3.toHSV(c)
                UpdateColor()
            end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end
end

function Library:CreateWindow(options)
    options = options or {}
    local Title = options.Title or "Linoria Lite"
    local Size = options.Size or UDim2.new(0, 550, 0, 450)
    
    local WindowObj = {
        Tabs = {},
        CurrentTab = nil
    }

    local ScreenGui = Create("ScreenGui", {
        Name = "LinoriaLiteGui",
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false
    })
    Library.ScreenGui = ScreenGui
    WindowObj.ScreenGui = ScreenGui
    
    local success = pcall(function() ScreenGui.Parent = CoreGui end)
    if not success then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    local TooltipOutline = Create("Frame", {
        Parent = ScreenGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Size = UDim2.new(0, 0, 0, 18),
        Visible = false,
        ZIndex = 10000,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local TooltipInline = Create("Frame", {
        Parent = TooltipOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local TooltipBg = Create("Frame", {
        Parent = TooltipInline,
        BackgroundColor3 = Library.Theme.BackgroundColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
    })
    local TooltipText = Create("TextLabel", {
        Parent = TooltipBg,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Library.Theme.Font,
        Text = "",
        TextColor3 = Library.Theme.TextColor,
        TextSize = 12,
ThemeMap = {TextColor3 = "TextColor"}
    })
    
    local function UpdateTooltip(text)
        if text and text ~= "" then
            local bounds = GetTextBounds(text, Library.Theme.Font, 12)
            TooltipOutline.Size = UDim2.new(0, bounds.X + 8, 0, 18)
            TooltipText.Text = text
            TooltipOutline.Visible = true
        else
            TooltipOutline.Visible = false
        end
    end
    
    local mouseConn = UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if TooltipOutline.Visible then
                TooltipOutline.Position = UDim2.new(0, input.Position.X + 15, 0, input.Position.Y + 15)
            end
        end
    end)
    table.insert(Library.Connections, mouseConn)

    WindowObj.ShowTooltip = function(text) UpdateTooltip(text) end
    WindowObj.HideTooltip = function() UpdateTooltip(nil) end

    -- Watermark UI
    local WatermarkOutline = Create("Frame", {
        Name = "Watermark",
        Parent = ScreenGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0, 15, 0, 15),
        Size = UDim2.new(0, 0, 0, 20),
        BorderSizePixel = 0,
        Visible = false,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local WmInline = Create("Frame", {
        Parent = WatermarkOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local WmBg = Create("Frame", {
        Parent = WmInline,
        BackgroundColor3 = Library.Theme.BackgroundColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
    })
    local WmAccent = Create("Frame", {
        Parent = WmBg,
        BackgroundColor3 = Library.Theme.AccentColor,
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "AccentColor"}
    })
    local WmText = Create("TextLabel", {
        Parent = WmBg,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Library.Theme.Font,
        Text = "",
        TextColor3 = Library.Theme.TextColor,
        TextSize = 12,
ThemeMap = {TextColor3 = "TextColor"}
    })
    
    function WindowObj:SetWatermark(text)
        WmText.Text = text
        if text == "" then
            WatermarkOutline.Visible = false
        else
            local bounds = GetTextBounds(text, Library.Theme.Font, 12)
            WatermarkOutline.Size = UDim2.new(0, bounds.X + 16, 0, 20)
            WatermarkOutline.Visible = true
        end
    end

    -- Notification UI
    local NotificationContainer = Create("Frame", {
        Name = "Notifications",
        Parent = ScreenGui,
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -15, 1, -15),
        Size = UDim2.new(0, 250, 0, 500),
        AnchorPoint = Vector2.new(1, 1)
    })
    local NotifLayout = Create("UIListLayout", {
        Parent = NotificationContainer,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Bottom
    })
    
    function WindowObj:Notify(text, duration)
        duration = duration or 3
        
        local bounds = GetTextBounds(text, Library.Theme.Font, 12)
        local NotifOutline = Create("Frame", {
            Parent = NotificationContainer,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(1, 0, 0, 24),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local NotifInline = Create("Frame", {
            Parent = NotifOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local NotifBg = Create("Frame", {
            Parent = NotifInline,
            BackgroundColor3 = Library.Theme.BackgroundColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
        })
        Create("Frame", {
            Parent = NotifBg,
            BackgroundColor3 = Library.Theme.AccentColor,
            Size = UDim2.new(0, 2, 1, 0),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "AccentColor"}
        })
        Create("TextLabel", {
            Parent = NotifBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -10, 1, 0),
            Font = Library.Theme.Font,
            Text = text,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })
        
        task.spawn(function()
            task.wait(duration)
            NotifOutline:Destroy()
        end)
    end

    local MainFrame = Create("Frame", {
        Name = "MainFrame",
        Parent = ScreenGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0.5, -Size.X.Offset/2, 0.5, -Size.Y.Offset/2),
        Size = Size,
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    
    local Inline = Create("Frame", {
        Name = "Inline",
        Parent = MainFrame,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })

    local WindowBg = Create("Frame", {
        Name = "WindowBg",
        Parent = Inline,
        BackgroundColor3 = Library.Theme.BackgroundColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
    })

    local Topbar = Create("Frame", {
        Name = "Topbar",
        Parent = WindowBg,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18)
    })
    MakeDraggable(Topbar, MainFrame)
    
    Create("TextLabel", {
        Name = "Title",
        Parent = Topbar,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 0),
        Size = UDim2.new(1, -12, 1, 0),
        Font = Library.Theme.Font,
        Text = Title,
        TextColor3 = Library.Theme.TextColor,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
    })
    
    Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0, 0, 0, 18),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 0, 0, 19),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })

    local TabContainer = Create("Frame", {
        Name = "TabContainer",
        Parent = WindowBg,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 20),
        Size = UDim2.new(1, 0, 0, 22)
    })
    
    local TabContainerLayout = Create("UIListLayout", {
        Parent = TabContainer,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder
    })

    local TabLine = Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 0, 0, 42),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        ZIndex = 1,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local TabLineShadow = Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0, 0, 0, 43),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        ZIndex = 1,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })

    local ContentContainer = Create("Frame", {
        Name = "ContentContainer",
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.MainColor,
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 1, -44),
        BorderSizePixel = 0,
        ZIndex = 2,
ThemeMap = {BackgroundColor3 = "MainColor"}
    })

    function WindowObj:CreateTab(name)
        local TabObj = {}
        
        local bounds = GetTextBounds(name, Library.Theme.Font, 12)
        local TabButton = Create("TextButton", {
            Name = name.."_Tab",
            Parent = TabContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, bounds.X + 16, 1, 0),
            BorderSizePixel = 0,
            Font = Library.Theme.Font,
            Text = "",
            ZIndex = 3
        })

        local TabBorder = Create("Frame", {
            Parent = TabButton,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(1, 0, 1, 2),
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 2,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local TabInline = Create("Frame", {
            Parent = TabBorder,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 3,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local TabBg = Create("Frame", {
            Parent = TabInline,
            BackgroundColor3 = Library.Theme.MainColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 4,
ThemeMap = {BackgroundColor3 = "MainColor"}
        })

        local TabText = Create("TextLabel", {
            Parent = TabButton,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 12,
            ZIndex = 5,
ThemeMap = {TextColor3 = "TextMuted"}
        })

        local TabContent = Create("ScrollingFrame", {
            Name = name.."_Content",
            Parent = ContentContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 0,
            Visible = false
        })

        local LeftCol = Create("Frame", {
            Name = "Left",
            Parent = TabContent,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 8, 0, 10),
            Size = UDim2.new(0.5, -12, 1, -20)
        })
        local LeftLayout = Create("UIListLayout", {
            Parent = LeftCol,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12)
        })

        local RightCol = Create("Frame", {
            Name = "Right",
            Parent = TabContent,
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, 4, 0, 10),
            Size = UDim2.new(0.5, -12, 1, -20)
        })
        local RightLayout = Create("UIListLayout", {
            Parent = RightCol,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12)
        })

        table.insert(WindowObj.Tabs, {
            Button = TabButton, 
            Content = TabContent,
            Border = TabBorder,
            Label = TabText
        })

        TabButton.MouseButton1Click:Connect(function()
            for _, tab in pairs(WindowObj.Tabs) do
                tab.Content.Visible = false
                tab.Label.TextColor3 = Library.Theme.TextMuted
                tab.Border.Visible = false
            end
            TabContent.Visible = true
            TabText.TextColor3 = Library.Theme.TextColor
            TabBorder.Visible = true
            WindowObj.CurrentTab = TabObj
        end)

        if #WindowObj.Tabs == 1 then
            TabContent.Visible = true
            TabText.TextColor3 = Library.Theme.TextColor
            TabBorder.Visible = true
            WindowObj.CurrentTab = TabObj
        end

        function TabObj:CreateGroupBox(side, groupName)
            local GroupObj = {}
            local ParentCol = side == "Left" and LeftCol or RightCol
            
            local GroupBoxOutline = Create("Frame", {
                Name = groupName.."_Group",
                Parent = ParentCol,
                BackgroundColor3 = Library.Theme.OutlineColor,
                Size = UDim2.new(1, 0, 0, 20),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
            })
            local GroupInline = Create("Frame", {
                Parent = GroupBoxOutline,
                BackgroundColor3 = Library.Theme.InlineColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
            })
            local GroupBg = Create("Frame", {
                Parent = GroupInline,
                BackgroundColor3 = Library.Theme.GroupBoxColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
            })

            local titleBounds = GetTextBounds(groupName, Library.Theme.Font, 12)
            local TitleLabel = Create("TextLabel", {
                Name = "Title",
                Parent = GroupBoxOutline,
                BackgroundColor3 = Library.Theme.MainColor,
                Position = UDim2.new(0, 8, 0, -6),
                Size = UDim2.new(0, titleBounds.X + 8, 0, 12),
                BorderSizePixel = 0,
                Font = Library.Theme.Font,
                Text = groupName,
                TextColor3 = Library.Theme.TextColor,
                TextSize = 12,
                ZIndex = 5,
ThemeMap = {BackgroundColor3 = "MainColor", TextColor3 = "TextColor"}
            })

            local ElementContainer = Create("Frame", {
                Name = "Container",
                Parent = GroupBg,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 10),
                Size = UDim2.new(1, 0, 1, -10)
            })
            
            local ContainerLayout = Create("UIListLayout", {
                Parent = ElementContainer,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6)
            })
            
            Create("UIPadding", {
                Parent = ElementContainer,
                PaddingLeft = UDim.new(0, 8),
                PaddingRight = UDim.new(0, 8),
                PaddingTop = UDim.new(0, 2),
                PaddingBottom = UDim.new(0, 8)
            })

            local function UpdateSize()
                GroupBoxOutline.Size = UDim2.new(1, 0, 0, 10 + ContainerLayout.AbsoluteContentSize.Y + 12)
                TabContent.CanvasSize = UDim2.new(0, 0, 0, math.max(LeftLayout.AbsoluteContentSize.Y, RightLayout.AbsoluteContentSize.Y) + 20)
            end
            
            ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSize)
            LeftLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSize)
            RightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSize)

            BindElementMethods(GroupObj, ElementContainer, WindowObj)
            return GroupObj
        end
        
        function TabObj:CreateTabBox(side)
            local TabBoxObj = {}
            local ParentCol = side == "Left" and LeftCol or RightCol
            
            local BoxOutline = Create("Frame", {
                Parent = ParentCol,
                BackgroundColor3 = Library.Theme.OutlineColor,
                Size = UDim2.new(1, 0, 0, 40),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
            })
            local BoxInline = Create("Frame", {
                Parent = BoxOutline,
                BackgroundColor3 = Library.Theme.InlineColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
            })
            local BoxBg = Create("Frame", {
                Parent = BoxInline,
                BackgroundColor3 = Library.Theme.GroupBoxColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
            })
            
            local TabButtonContainer = Create("Frame", {
                Parent = BoxBg,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 20)
            })
            
            local SepLine = Create("Frame", {
                Parent = BoxBg,
                BackgroundColor3 = Library.Theme.InlineColor,
                Position = UDim2.new(0, 0, 0, 20),
                Size = UDim2.new(1, 0, 0, 1),
                BorderSizePixel = 0,
                ZIndex = 2,
ThemeMap = {BackgroundColor3 = "InlineColor"}
            })
            local SepShadow = Create("Frame", {
                Parent = BoxBg,
                BackgroundColor3 = Library.Theme.OutlineColor,
                Position = UDim2.new(0, 0, 0, 21),
                Size = UDim2.new(1, 0, 0, 1),
                BorderSizePixel = 0,
                ZIndex = 2,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
            })
            
            local ContentArea = Create("Frame", {
                Parent = BoxBg,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 22),
                Size = UDim2.new(1, 0, 1, -22)
            })

            local SubTabs = {}

            local function UpdateTabBoxSize()
                local maxHeight = 0
                for _, tab in ipairs(SubTabs) do
                    if tab.Layout.AbsoluteContentSize.Y > maxHeight then
                        maxHeight = tab.Layout.AbsoluteContentSize.Y
                    end
                end
                BoxOutline.Size = UDim2.new(1, 0, 0, 22 + maxHeight + 12)
                TabContent.CanvasSize = UDim2.new(0, 0, 0, math.max(LeftLayout.AbsoluteContentSize.Y, RightLayout.AbsoluteContentSize.Y) + 20)
            end

            function TabBoxObj:AddTab(name)
                local SubTabObj = {}
                
                local TabBtn = Create("TextButton", {
                    Parent = TabButtonContainer,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 1, 0),
                    Font = Library.Theme.Font,
                    Text = name,
                    TextColor3 = Library.Theme.TextMuted,
                    TextSize = 12,
ThemeMap = {TextColor3 = "TextMuted"}
                })

                local RightLine = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.InlineColor,
                    Position = UDim2.new(1, -1, 0, 0),
                    Size = UDim2.new(0, 1, 1, 0),
                    BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
                })
                local RightShadow = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.OutlineColor,
                    Position = UDim2.new(1, 0, 0, 0),
                    Size = UDim2.new(0, 1, 1, 0),
                    BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
                })

                local ActiveCover = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.GroupBoxColor,
                    Position = UDim2.new(0, 0, 1, 0),
                    Size = UDim2.new(1, 0, 0, 2),
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 3,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
                })

                local AccentLine = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.AccentColor,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 4,
ThemeMap = {BackgroundColor3 = "AccentColor"}
                })
                
                Create("UIGradient", {
                    Parent = AccentLine,
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.new(0.2, 0.2, 0.2)),
                        ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
                        ColorSequenceKeypoint.new(1, Color3.new(0.2, 0.2, 0.2))
                    })
                })

                local ElementContainer = Create("Frame", {
                    Parent = ContentArea,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    Visible = false
                })
                
                local ContainerLayout = Create("UIListLayout", {
                    Parent = ElementContainer,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 6)
                })
                
                Create("UIPadding", {
                    Parent = ElementContainer,
                    PaddingLeft = UDim.new(0, 8),
                    PaddingRight = UDim.new(0, 8),
                    PaddingTop = UDim.new(0, 6),
                    PaddingBottom = UDim.new(0, 8)
                })

                table.insert(SubTabs, {
                    Button = TabBtn,
                    Container = ElementContainer,
                    Cover = ActiveCover,
                    Accent = AccentLine,
                    RightLine = RightLine,
                    RightShadow = RightShadow,
                    Layout = ContainerLayout
                })

                local count = #SubTabs
                for i, tab in ipairs(SubTabs) do
                    tab.Button.Size = UDim2.new(1/count, i == count and 0 or -2, 1, 0)
                    tab.Button.Position = UDim2.new((i-1)/count, 0, 0, 0)
                    if i == count then
                        tab.RightLine.Visible = false
                        tab.RightShadow.Visible = false
                    else
                        tab.RightLine.Visible = true
                        tab.RightShadow.Visible = true
                    end
                end

                ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateTabBoxSize)
                LeftLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateTabBoxSize)
                RightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateTabBoxSize)

                TabBtn.MouseButton1Click:Connect(function()
                    for _, tab in pairs(SubTabs) do
                        tab.Container.Visible = false
                        tab.Button.TextColor3 = Library.Theme.TextMuted
                        tab.Cover.Visible = false
                        tab.Accent.Visible = false
                    end
                    ElementContainer.Visible = true
                    TabBtn.TextColor3 = Library.Theme.TextColor
                    ActiveCover.Visible = true
                    AccentLine.Visible = true
                end)

                if #SubTabs == 1 then
                    ElementContainer.Visible = true
                    TabBtn.TextColor3 = Library.Theme.TextColor
                    ActiveCover.Visible = true
                    AccentLine.Visible = true
                end

                BindElementMethods(SubTabObj, ElementContainer, WindowObj)
                return SubTabObj
            end
            
            return TabBoxObj
        end
        
        return TabObj
    end

    return WindowObj
end

return Library
