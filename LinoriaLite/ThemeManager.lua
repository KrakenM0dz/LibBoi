local HttpService = game:GetService("HttpService")

local ThemeManager = {}
ThemeManager.Folder = "LinoriaLiteSettings"
ThemeManager.Library = nil

ThemeManager.BuiltInThemes = {
    ['Default']         = { 1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1c1c","AccentColor":"0055ff","BackgroundColor":"141414","OutlineColor":"323232"}') },
    ['BBot']            = { 2, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor":"7e48a3","BackgroundColor":"232323","OutlineColor":"141414"}') },
    ['Fatality']        = { 3, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1842","AccentColor":"c50754","BackgroundColor":"191335","OutlineColor":"3c355d"}') },
    ['Jester']          = { 4, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"db4467","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
    ['Mint']            = { 5, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"3db488","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
    ['Tokyo Night']     = { 6, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6759b3","BackgroundColor":"16161f","OutlineColor":"323232"}') },
    ['Ubuntu']          = { 7, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"3e3e3e","AccentColor":"e2581e","BackgroundColor":"323232","OutlineColor":"191919"}') },
    ['Quartz']          = { 8, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"232330","AccentColor":"426e87","BackgroundColor":"1d1b26","OutlineColor":"27232f"}') }
}

function ThemeManager:SetLibrary(lib)
    self.Library = lib
end

function ThemeManager:SetFolder(folderName)
    self.Folder = folderName
    if isfolder and not isfolder(self.Folder) then
        makefolder(self.Folder)
    end
    if isfolder and not isfolder(self.Folder .. "/themes") then
        makefolder(self.Folder .. "/themes")
    end
end

-- Safely converts a hex string to a Color3
local function ParseHex(hexStr)
    hexStr = hexStr:gsub("#","")
    local r = tonumber(hexStr:sub(1,2), 16) or 255
    local g = tonumber(hexStr:sub(3,4), 16) or 255
    local b = tonumber(hexStr:sub(5,6), 16) or 255
    return Color3.fromRGB(r, g, b)
end

-- Safely converts a Color3 to a hex string
local function ToHex(color)
    local r = math.clamp(math.round(color.R * 255), 0, 255)
    local g = math.clamp(math.round(color.G * 255), 0, 255)
    local b = math.clamp(math.round(color.B * 255), 0, 255)
    return string.format("%02x%02x%02x", r, g, b)
end

function ThemeManager:ApplyTheme(theme)
    local themeData = theme
    if type(theme) == "table" and theme[2] then
        themeData = theme[2]
    end

    local newTheme = {}
    
    -- Extract core colors from themeData
    for key, val in pairs(themeData) do
        if key == "FontColor" then key = "TextColor" end -- Backwards compatibility
        
        if typeof(val) == "Color3" then
            newTheme[key] = val
        elseif type(val) == "string" then
            newTheme[key] = ParseHex(val)
        elseif type(val) == "table" then
            local r = val.R or val.r or val[1] or 1
            local g = val.G or val.g or val[2] or 1
            local b = val.B or val.b or val[3] or 1
            if r > 1 or g > 1 or b > 1 then
                newTheme[key] = Color3.fromRGB(r, g, b)
            else
                newTheme[key] = Color3.new(r, g, b)
            end
        end
    end

    -- Derive secondary colors safely using Color3.new
    if newTheme.BackgroundColor then
        newTheme.GroupBoxColor = newTheme.BackgroundColor
    end
    
    if newTheme.MainColor then
        newTheme.InlineColor = Color3.new(
            math.clamp(newTheme.MainColor.R + (30/255), 0, 1),
            math.clamp(newTheme.MainColor.G + (30/255), 0, 1),
            math.clamp(newTheme.MainColor.B + (30/255), 0, 1)
        )
    end
    
    if newTheme.TextColor then
        newTheme.TextMuted = Color3.new(
            newTheme.TextColor.R * 0.588,
            newTheme.TextColor.G * 0.588,
            newTheme.TextColor.B * 0.588
        )
    end

    -- Update library theme
    for key, color in pairs(newTheme) do
        if self.Library.Theme[key] ~= nil then
            self.Library:UpdateTheme(key, color)
            
            -- Update UI Pickers if they exist
            local picker = self.Library.Options["ThemeManager_" .. key]
            if picker then
                pcall(function() picker:SetValue(color) end)
            end
        end
    end
end

function ThemeManager:RefreshCustomThemes()
    local list = {}
    if listfiles and isfolder and isfolder(self.Folder .. "/themes") then
        for _, file in ipairs(listfiles(self.Folder .. "/themes")) do
            if file:sub(-5) == ".json" then
                local fileName = file:match("([^/\\]+)%.json$")
                if fileName then
                    table.insert(list, fileName)
                end
            end
        end
    end
    return list
end

function ThemeManager:SaveCustomTheme(name)
    if not writefile then return false end
    
    local themeData = {
        BackgroundColor = ToHex(self.Library.Theme.BackgroundColor),
        MainColor = ToHex(self.Library.Theme.MainColor),
        AccentColor = ToHex(self.Library.Theme.AccentColor),
        OutlineColor = ToHex(self.Library.Theme.OutlineColor),
        FontColor = ToHex(self.Library.Theme.TextColor),
    }
    
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, themeData)
    if success then
        writefile(self.Folder .. "/themes/" .. name .. ".json", encoded)
        return true
    end
    return false
end

function ThemeManager:LoadCustomTheme(name)
    if not readfile then return false end
    
    local success, content = pcall(readfile, self.Folder .. "/themes/" .. name .. ".json")
    if not success then return false end
    
    local decodedSuccess, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not decodedSuccess or type(data) ~= "table" then return false end
    
    self:ApplyTheme(data)
    return true
end

function ThemeManager:LoadDefaultTheme()
    if not readfile then return end
    local success, content = pcall(readfile, self.Folder .. "/themes/default.txt")
    
    if success and content ~= "" then
        if self.BuiltInThemes[content] then
            self:ApplyTheme(self.BuiltInThemes[content])
            if self.Library.Options.ThemeManager_ThemeList then
                self.Library.Options.ThemeManager_ThemeList:SetValue(content)
            end
        else
            self:LoadCustomTheme(content)
            if self.Library.Options.ThemeManager_CustomThemeList then
                self.Library.Options.ThemeManager_CustomThemeList:SetValue(content)
            end
        end
    end
end

function ThemeManager:BuildThemeSection(Tab)
    local ThemeGroup = Tab:CreateGroupBox("Left", "Themes")
    
    ThemeGroup:AddColorPicker("Background color", self.Library.Theme.BackgroundColor, function(color)
        self.Library:UpdateTheme("BackgroundColor", color)
        self.Library:UpdateTheme("GroupBoxColor", color)
    end, "ThemeManager_BackgroundColor")
    
    ThemeGroup:AddColorPicker("Main color", self.Library.Theme.MainColor, function(color)
        self.Library:UpdateTheme("MainColor", color)
        local inline = Color3.new(
            math.clamp(color.R + (30/255), 0, 1),
            math.clamp(color.G + (30/255), 0, 1),
            math.clamp(color.B + (30/255), 0, 1)
        )
        self.Library:UpdateTheme("InlineColor", inline)
    end, "ThemeManager_MainColor")
    
    ThemeGroup:AddColorPicker("Accent color", self.Library.Theme.AccentColor, function(color)
        self.Library:UpdateTheme("AccentColor", color)
    end, "ThemeManager_AccentColor")
    
    ThemeGroup:AddColorPicker("Outline color", self.Library.Theme.OutlineColor, function(color)
        self.Library:UpdateTheme("OutlineColor", color)
    end, "ThemeManager_OutlineColor")
    
    ThemeGroup:AddColorPicker("Font color", self.Library.Theme.TextColor, function(color)
        self.Library:UpdateTheme("TextColor", color)
        local muted = Color3.new(
            color.R * 0.588,
            color.G * 0.588,
            color.B * 0.588
        )
        self.Library:UpdateTheme("TextMuted", muted)
    end, "ThemeManager_TextColor")
    
    local builtinList = {}
    for k, v in pairs(self.BuiltInThemes) do 
        builtinList[v[1]] = k 
    end
    
    ThemeGroup:AddDropdown("Theme list", builtinList, "Default", function(theme)
        if self.BuiltInThemes[theme] then
            self:ApplyTheme(self.BuiltInThemes[theme])
        end
    end, "ThemeManager_ThemeList")
    
    ThemeGroup:AddButton("Set as default", function()
        local name = self.Library.Options.ThemeManager_ThemeList.Value
        if writefile then
            writefile(self.Folder .. "/themes/default.txt", name)
            self.Library:Notify("Set default theme to: " .. name)
        end
    end)
    
    ThemeGroup:AddInput("Custom theme name", "", function() end, "ThemeManager_CustomThemeName")
    local customList = ThemeGroup:AddDropdown("Custom themes", self:RefreshCustomThemes(), nil, function() end, "ThemeManager_CustomThemeList")
    
    ThemeGroup:AddButton("Save theme", function()
        local name = self.Library.Options.ThemeManager_CustomThemeName.Value
        if name and name ~= "" then
            self:SaveCustomTheme(name)
            customList:RefreshOptions(self:RefreshCustomThemes())
            customList:SetValue(name)
            self.Library:Notify("Saved custom theme: " .. name)
        end
    end)
    
    ThemeGroup:AddButton("Load theme", function()
        local name = self.Library.Options.ThemeManager_CustomThemeList.Value
        if name and name ~= "" then
            local success = self:LoadCustomTheme(name)
            if success then
                self.Library:Notify("Loaded custom theme: " .. name)
            else
                self.Library:Notify("Failed to load theme: " .. name)
            end
        end
    end)
    
    ThemeGroup:AddButton("Refresh list", function()
        customList:RefreshOptions(self:RefreshCustomThemes())
    end)
end

return ThemeManager
