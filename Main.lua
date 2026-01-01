
local KeyAuth = {}
KeyAuth.__index = KeyAuth

function KeyAuth:new(name, ownerid, secret, version)
    local self = setmetatable({}, KeyAuth)
    self.name = name
    self.ownerid = ownerid
    self.secret = secret
    self.version = version
    self.api_url = "https://keyauth.win/api/1.2/"
    self.sessionid = ""
    self.initialized = false
    self.user_data = nil
    return self
end

function KeyAuth:init()
    local response = game:HttpGet(
        self.api_url ..
        "?type=init&name=" .. self.name ..
        "&ownerid=" .. self.ownerid ..
        "&secret=" .. self.secret ..
        "&version=" .. self.version
    )

    local data = game:GetService("HttpService"):JSONDecode(response)

    if data and data.success then
        self.sessionid = data.sessionid
        self.initialized = true
        return true
    end

    return false, data and data.message or "Init failed"
end

function KeyAuth:license(key)
    if not self.initialized then
        return false, "Not initialized"
    end

    local response = game:HttpGet(
        self.api_url ..
        "?type=license&key=" .. key ..
        "&name=" .. self.name ..
        "&ownerid=" .. self.ownerid ..
        "&sessionid=" .. self.sessionid
    )

    local data = game:GetService("HttpService"):JSONDecode(response)

    if data and data.success then
        self.user_data = data.info
        return true
    end

    return false, data and data.message or "Invalid key"
end

-- =========================================================
-- CONFIG
-- =========================================================

local KeyAuthApp = KeyAuth:new(
    "Reallegend6759's Application",
    "TT5SBxlpqE",
    "10910a7c5f78d535c96e84ac2c0b1b1aa08339cefb68b53657a75858609ca83d",
    "1.0"
)

local KeyLink = "https://lootdest.org/s?4tOIru3g"

local ok, err = KeyAuthApp:init()
if not ok then
    warn("KeyAuth Init Failed:", err)
end

-- =========================================================
-- MAIN SCRIPT LOADER (UNCHANGED URL)
-- =========================================================

local function ScriptHere()
    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/SleepyCattStar/CattStar/refs/heads/main/MainScript_..lua"
    ))()
end

-- =========================================================
-- UI
-- =========================================================

local Players = game:GetService("Players")
local G2L = {}

-- ScreenGui
G2L["1"] = Instance.new("ScreenGui")
G2L["1"].Name = "KeySystem"
G2L["1"].ResetOnSpawn = false
G2L["1"].Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Main Frame
G2L["2"] = Instance.new("Frame", G2L["1"])
G2L["2"].Size = UDim2.new(0.35, 0, 0.8, 0)
G2L["2"].Position = UDim2.new(0.325, 0, 0.1, 0)
G2L["2"].BackgroundColor3 = Color3.fromRGB(30, 30, 30)
G2L["2"].BorderSizePixel = 0

-- Title
G2L["3"] = Instance.new("TextLabel", G2L["2"])
G2L["3"].Text = "Key System"
G2L["3"].Size = UDim2.new(1, 0, 0.15, 0)
G2L["3"].BackgroundTransparency = 1
G2L["3"].TextColor3 = Color3.new(1, 1, 1)
G2L["3"].Font = Enum.Font.GothamBold
G2L["3"].TextScaled = true

-- =========================
-- KEY INPUT
-- =========================

G2L["4"] = Instance.new("Frame", G2L["2"])
G2L["4"].Size = UDim2.new(0.88, 0, 0.12, 0)
G2L["4"].Position = UDim2.new(0.06, 0, 0.25, 0)
G2L["4"].BackgroundColor3 = Color3.fromRGB(50, 50, 50)
G2L["4"].BorderSizePixel = 0

G2L["5"] = Instance.new("TextBox", G2L["4"])
G2L["5"].Size = UDim2.new(1, 0, 1, 0)
G2L["5"].BackgroundTransparency = 1
G2L["5"].PlaceholderText = "Enter License Key Here"
G2L["5"].TextColor3 = Color3.new(1, 1, 1)
G2L["5"].Font = Enum.Font.Gotham
G2L["5"].TextScaled = true

-- =========================
-- LINK DISPLAY (NEW)
-- =========================

G2L["6"] = Instance.new("Frame", G2L["2"])
G2L["6"].Size = UDim2.new(0.88, 0, 0.12, 0)
G2L["6"].Position = UDim2.new(0.06, 0, 0.40, 0)
G2L["6"].BackgroundColor3 = Color3.fromRGB(45, 45, 45)
G2L["6"].BorderSizePixel = 0

G2L["7"] = Instance.new("TextBox", G2L["6"])
G2L["7"].Size = UDim2.new(1, 0, 1, 0)
G2L["7"].BackgroundTransparency = 1
G2L["7"].Text = ""
G2L["7"].ClearTextOnFocus = false
G2L["7"].PlaceholderText = "Click 'Get Key' to show link"
G2L["7"].TextEditable = false
G2L["7"].TextWrapped = true
G2L["7"].TextColor3 = Color3.fromRGB(200, 200, 200)
G2L["7"].Font = Enum.Font.Gotham
G2L["7"].TextScaled = true

-- =========================
-- VERIFY BUTTON
-- =========================

G2L["8"] = Instance.new("TextButton", G2L["2"])
G2L["8"].Size = UDim2.new(0.88, 0, 0.12, 0)
G2L["8"].Position = UDim2.new(0.06, 0, 0.58, 0)
G2L["8"].Text = "Verify Key"
G2L["8"].BackgroundColor3 = Color3.fromRGB(0, 170, 255)
G2L["8"].Font = Enum.Font.GothamBold
G2L["8"].TextScaled = true

G2L["8"].MouseButton1Click:Connect(function()
    G2L["3"].Text = "Verifying..."

    local success = KeyAuthApp:license(G2L["5"].Text)

    if success then
        G2L["3"].Text = "Access Granted!"
        task.wait(1)
        G2L["1"]:Destroy()
        ScriptHere()
    else
        G2L["3"].Text = "Invalid Key!"
        task.wait(2)
        G2L["3"].Text = "Key System"
    end
end)

-- =========================
-- GET KEY BUTTON
-- =========================

G2L["9"] = Instance.new("TextButton", G2L["2"])
G2L["9"].Size = UDim2.new(0.88, 0, 0.12, 0)
G2L["9"].Position = UDim2.new(0.06, 0, 0.72, 0)
G2L["9"].Text = "Get Key (LootLabs)"
G2L["9"].BackgroundColor3 = Color3.fromRGB(80, 80, 80)
G2L["9"].Font = Enum.Font.GothamBold
G2L["9"].TextScaled = true

G2L["9"].MouseButton1Click:Connect(function()
    G2L["7"].Text = KeyLink
    G2L["3"].Text = "Link Shown Below"
    task.wait(2)
    G2L["3"].Text = "Key System"
end)

return G2L["1"]