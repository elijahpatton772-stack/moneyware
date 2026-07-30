--[[
    ███╗   ███╗ ██████╗ ███╗   ██╗███████╗██╗   ██╗██╗    ██╗ █████╗ ██████╗ ███████╗
    ████╗ ████║██╔═══██╗████╗  ██║██╔════╝╚██╗ ██╔╝██║    ██║██╔══██╗██╔══██╗██╔════╝
    ██╔████╔██║██║   ██║██╔██╗ ██║█████╗   ╚████╔╝ ██║ █╗ ██║███████║██████╔╝█████╗  
    ██║╚██╔╝██║██║   ██║██║╚██╗██║██╔══╝    ╚██╔╝  ██║███╗██║██╔══██║██╔══██╗██╔══╝  
    ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████╗   ██║   ╚███╔███╔╝██║  ██║██║  ██║███████╗
    ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

    v1.1  —  Da Hood / Zee Hood
    Hitbox Expander + Dead Check + Whitelist + Profile/Cinematic ESP + 4D Display

    v1.1 FIXES
      • removed read-only signal assignment that killed the load (hard crash)
      • camera is now resolved live, never cached across respawns
      • per-player character cache — no FindFirstChild spam on RenderStepped
      • ESP throttled + budgeted; objects only built when ESP is on
      • dropdown menus render on an overlay layer (no more clipping)
      • zero external asset ids — nothing to fail to load or get moderated
      • every build block is fault-isolated: one broken section can't kill the rest
      • unload iterates a snapshot, never mutates a table mid-pairs
      • hitbox tween-flood fixed with per-part state tracking
]]

--============================================================================--
--  0. GUARD / SERVICES
--============================================================================--

if getgenv and getgenv().MoneyWareUnload then
    pcall(getgenv().MoneyWareUnload)
end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")
local Stats            = game:GetService("Stats")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- ALWAYS resolve the camera live. Roblox replaces it on respawn.
local function cam()
    return Workspace.CurrentCamera
end

local Connections = {}
local Alive = true

local function bind(signal, fn)
    local ok, c = pcall(function()
        return signal:Connect(function(...)
            if not Alive then return end
            local s, e = pcall(fn, ...)
            if not s then warn("[MoneyWare] handler error: " .. tostring(e)) end
        end)
    end)
    if ok and c then table.insert(Connections, c) end
    return c
end

--============================================================================--
--  1. CONFIG
--============================================================================--

local Config = {
    HitboxEnabled  = false,
    HitboxMode     = "Resize",  -- Resize = edits their REAL HumanoidRootPart, re-applied EVERY FRAME so the game
                                -- can't shrink it back. This is the proven Da Hood method -> shots register.
                                -- Proxy = welded, massless, unanchored part (also every-frame). Try this if Resize won't hit.
    ProxyName      = "HumanoidRootPart",
    HitboxPart     = "HumanoidRootPart",
    HitboxSize     = 12,
    HitboxTrans    = 0.65,
    HitboxMaterial = "ForceField",
    HitboxColor    = Color3.fromRGB(255, 60, 90),
    HitboxCollide  = false,
    HitboxMassless = true,
    PhaseThrough   = true,   -- force CanCollide off on the physics frame
    NoTouch        = false,  -- also kill Touched events on the expanded part
    LowImpact      = false,  -- skip Massless/Material entirely (zero mass recompute)
    PartFallback   = true,   -- resolve R15 equivalents / fall back to root
    AutoWhitelist  = true,   -- everyone who joins becomes a target automatically
    ForceAll       = true,   -- hard override: literally every player, no filters
    JointGuard     = true,   -- cut any weld the game attaches to our proxy
    ReleaseOnGrab  = true,   -- drop the proxy while a player is being carried
    GhostDowned    = false,  -- walk through knocked players' actual ragdoll bodies
    HitboxSmooth   = false,  -- tweened Size = 11 frames of mass recompute; off by default
    DeadCheck      = true,
    KOCheck        = true,
    TeamCheck      = false,
    HitboxRefresh  = 0.10,

    -- TRIGGERBOT ------------------------------------------------------------
    TriggerEnabled   = false,
    TriggerDelay     = 0,       -- ms to wait after a target enters the cursor before the FIRST shot (0 = instant)
    TriggerRate      = 60,      -- ms between shots while the cursor stays on a target (lower = faster)
    TriggerMaxDist   = 1000,    -- studs; targets past this are ignored
    TriggerDeadCheck = true,    -- never waste rounds on knocked/dead players
    TriggerTeamCheck = false,   -- skip teammates
    TriggerWallCheck = true,    -- only fire when the target is actually in line of sight (no shooting through walls)
    TriggerHoldMode  = false,   -- true = only fire while the hold key is down; false = always active
    TriggerKey       = Enum.KeyCode.E,
    TriggerGunOnly   = false,   -- true = only fire when a tool is equipped (skip melee/fists)
    TriggerRespectWL = true,    -- true = only fire at people who pass the Targets tab (whitelist/blacklist)

    WhitelistMode  = "Everyone",
    Whitelisted    = {},
    Blacklisted    = {},

    EspEnabled     = false,
    EspStyle       = "Profile",
    EspBox         = true,
    EspBoxStyle    = "Corner",
    EspName        = true,
    EspHealth      = true,
    EspDistance    = true,
    EspTool        = true,
    EspTracer      = false,
    EspTracerFrom  = "Bottom",
    EspChams       = false,
    EspArrows      = true,
    EspAvatarSize  = 46,
    EspMaxDistance = 2500,
    EspTeamColor   = false,
    EspDeadFade    = true,
    EspRainbow     = false,
    EspRate        = 60,

    UIScale        = 1.00,
    Keybind        = Enum.KeyCode.RightShift,
    Watermark      = true,
    Theme          = "Midnight Bloom",
    ActivePreset   = "default",
}

--============================================================================--
--  2. THEMES (24)
--============================================================================--

local function C3(r, g, b) return Color3.fromRGB(r, g, b) end

local Themes = {
    ["Midnight Bloom"] = {Accent=C3(138,110,255), Accent2=C3(90,190,255),  Bg=C3(13,13,18),  Panel=C3(19,19,26),  Card=C3(25,25,34),  Stroke=C3(42,42,58),  Text=C3(238,238,248), Sub=C3(138,138,158)},
    ["Blood Orchid"]   = {Accent=C3(255,58,92),   Accent2=C3(255,140,110), Bg=C3(15,10,12),  Panel=C3(22,14,17),  Card=C3(30,19,23),  Stroke=C3(58,30,38),  Text=C3(255,240,242), Sub=C3(160,120,128)},
    ["Cyber Lime"]     = {Accent=C3(170,255,60),  Accent2=C3(60,255,180),  Bg=C3(10,14,10),  Panel=C3(15,20,15),  Card=C3(21,28,21),  Stroke=C3(40,58,40),  Text=C3(238,255,238), Sub=C3(130,160,130)},
    ["Deep Ocean"]     = {Accent=C3(40,160,255),  Accent2=C3(0,225,220),   Bg=C3(8,12,20),   Panel=C3(12,18,28),  Card=C3(17,25,38),  Stroke=C3(30,48,72),  Text=C3(232,242,255), Sub=C3(120,145,175)},
    ["Sakura"]         = {Accent=C3(255,140,190), Accent2=C3(255,190,220), Bg=C3(20,14,18),  Panel=C3(28,19,25),  Card=C3(37,25,33),  Stroke=C3(66,42,56),  Text=C3(255,238,246), Sub=C3(178,140,158)},
    ["Vaporwave"]      = {Accent=C3(255,90,220),  Accent2=C3(90,220,255),  Bg=C3(14,8,22),   Panel=C3(21,12,32),  Card=C3(28,16,42),  Stroke=C3(58,30,84),  Text=C3(245,235,255), Sub=C3(150,125,180)},
    ["Solar Flare"]    = {Accent=C3(255,168,20),  Accent2=C3(255,88,40),   Bg=C3(18,13,8),   Panel=C3(26,18,11),  Card=C3(34,24,15),  Stroke=C3(64,45,25),  Text=C3(255,246,232), Sub=C3(172,146,112)},
    ["Toxic Waste"]    = {Accent=C3(120,255,40),  Accent2=C3(220,255,0),   Bg=C3(9,13,7),    Panel=C3(14,19,11),  Card=C3(19,26,15),  Stroke=C3(38,54,28),  Text=C3(236,255,228), Sub=C3(128,154,116)},
    ["Arctic"]         = {Accent=C3(150,220,255), Accent2=C3(255,255,255), Bg=C3(12,16,20),  Panel=C3(18,23,29),  Card=C3(25,31,38),  Stroke=C3(46,56,68),  Text=C3(240,248,255), Sub=C3(140,158,175)},
    ["Blackout"]       = {Accent=C3(235,235,235), Accent2=C3(160,160,160), Bg=C3(6,6,6),     Panel=C3(11,11,11),  Card=C3(16,16,16),  Stroke=C3(32,32,32),  Text=C3(245,245,245), Sub=C3(120,120,120)},
    ["Bubblegum"]      = {Accent=C3(255,105,180), Accent2=C3(120,200,255), Bg=C3(18,12,18),  Panel=C3(26,17,26),  Card=C3(34,23,34),  Stroke=C3(62,40,62),  Text=C3(255,240,250), Sub=C3(168,132,158)},
    ["Emerald"]        = {Accent=C3(0,220,140),   Accent2=C3(120,255,200), Bg=C3(8,15,12),   Panel=C3(12,22,18),  Card=C3(16,30,24),  Stroke=C3(30,58,46),  Text=C3(232,255,246), Sub=C3(118,158,142)},
    ["Royal"]          = {Accent=C3(110,90,255),  Accent2=C3(190,160,255), Bg=C3(11,10,18),  Panel=C3(16,15,27),  Card=C3(22,20,36),  Stroke=C3(42,38,68),  Text=C3(238,236,255), Sub=C3(136,132,168)},
    ["Rust"]           = {Accent=C3(198,92,48),   Accent2=C3(240,150,90),  Bg=C3(16,12,10),  Panel=C3(24,17,14),  Card=C3(32,23,19),  Stroke=C3(60,42,33),  Text=C3(255,240,232), Sub=C3(164,136,120)},
    ["Matrix"]         = {Accent=C3(0,255,90),    Accent2=C3(0,180,60),    Bg=C3(4,8,5),     Panel=C3(7,13,8),    Card=C3(10,19,12),  Stroke=C3(22,46,28),  Text=C3(190,255,205), Sub=C3(88,150,105)},
    ["Sunset Drive"]   = {Accent=C3(255,110,140), Accent2=C3(255,190,110), Bg=C3(17,11,16),  Panel=C3(25,16,23),  Card=C3(33,22,31),  Stroke=C3(62,40,56),  Text=C3(255,242,244), Sub=C3(170,136,148)},
    ["Steel"]          = {Accent=C3(120,150,180), Accent2=C3(180,205,230), Bg=C3(13,15,17),  Panel=C3(19,22,25),  Card=C3(26,30,34),  Stroke=C3(48,54,62),  Text=C3(236,242,248), Sub=C3(132,146,160)},
    ["Amethyst"]       = {Accent=C3(180,100,255), Accent2=C3(230,170,255), Bg=C3(13,9,18),   Panel=C3(20,14,28),  Card=C3(27,19,37),  Stroke=C3(52,36,72),  Text=C3(245,236,255), Sub=C3(150,130,172)},
    ["Coral Reef"]     = {Accent=C3(255,120,100), Accent2=C3(90,230,220),  Bg=C3(12,15,16),  Panel=C3(18,22,24),  Card=C3(24,30,32),  Stroke=C3(46,58,62),  Text=C3(238,250,250), Sub=C3(130,152,155)},
    ["Gold Rush"]      = {Accent=C3(255,205,70),  Accent2=C3(255,240,170), Bg=C3(14,12,7),   Panel=C3(21,18,11),  Card=C3(28,24,15),  Stroke=C3(56,47,26),  Text=C3(255,250,230), Sub=C3(168,152,110)},
    ["Ultraviolet"]    = {Accent=C3(150,0,255),   Accent2=C3(255,0,190),   Bg=C3(9,6,16),    Panel=C3(14,9,25),   Card=C3(20,13,34),  Stroke=C3(44,24,72),  Text=C3(240,232,255), Sub=C3(142,120,172)},
    ["Sandstorm"]      = {Accent=C3(226,190,130), Accent2=C3(255,225,180), Bg=C3(16,14,11),  Panel=C3(23,20,16),  Card=C3(31,27,22),  Stroke=C3(58,51,41),  Text=C3(252,246,236), Sub=C3(162,150,130)},
    ["Nightshade"]     = {Accent=C3(70,90,255),   Accent2=C3(140,90,255),  Bg=C3(7,8,14),    Panel=C3(11,13,21),  Card=C3(15,18,29),  Stroke=C3(30,36,58),  Text=C3(230,234,255), Sub=C3(118,126,158)},
    ["Crimson Steel"]  = {Accent=C3(220,40,60),   Accent2=C3(120,140,160), Bg=C3(11,11,13),  Panel=C3(16,16,19),  Card=C3(22,22,26),  Stroke=C3(44,44,52),  Text=C3(242,242,246), Sub=C3(126,126,138)},
}

local Theme = Themes[Config.Theme]
local ThemedObjects = {}

local function themed(inst, prop, key)
    if not inst then return inst end
    table.insert(ThemedObjects, {inst = inst, prop = prop, key = key})
    pcall(function() inst[prop] = Theme[key] end)
    return inst
end

-- release an object from theme control, for widgets that drive their own color
local function unthemed(inst)
    for i = #ThemedObjects, 1, -1 do
        if ThemedObjects[i].inst == inst then table.remove(ThemedObjects, i) end
    end
    return inst
end

--============================================================================--
--  3. UTILITY
--============================================================================--

local function new(class, props, children)
    local o = Instance.new(class)
    local parent = nil
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            local ok, err = pcall(function() o[k] = v end)
            if not ok then warn(("[MoneyWare] %s.%s failed: %s"):format(class, tostring(k), tostring(err))) end
        end
    end
    for _, c in ipairs(children or {}) do c.Parent = o end
    if parent then o.Parent = parent end
    return o
end

local function corner(parent, r)
    if not parent then return end
    return new("UICorner", {CornerRadius = UDim.new(0, r or 8), Parent = parent})
end

local function stroke(parent, key, thick, trans)
    if not parent then return end
    local s = new("UIStroke", {
        Thickness = thick or 1,
        Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
    if key then themed(s, "Color", key) end
    return s
end

local function pad(parent, l, r, t, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        Parent = parent,
    })
end

local function tween(o, t, props, style)
    if not o or not o.Parent then return end
    local ok, tw = pcall(function()
        return TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    end)
    if ok and tw then tw:Play() return tw end
end

local function round(n, d) local m = 10 ^ (d or 0) return math.floor(n * m + 0.5) / m end

--============================================================================--
--  3.5 MOTION + CHROME PRIMITIVES  (the "art piece" layer)
--
--  Everything here is pure Instance work — zero asset ids, same promise the
--  engine keeps. Depth, glow and life are faked with gradients, concentric
--  rings and one per-frame animation driver instead of imported images.
--============================================================================--

-- living-UI animation registries, pumped from the render loop.
--   AnimWin : window chrome — ONLY runs while the menu is on screen (0 cost closed)
--   AnimWM  : the persistent watermark HUD — a couple of tiny always-on anims
local AnimWin, AnimWM = {}, {}
local function animate(fn)   table.insert(AnimWin, fn); return fn end
local function animateWM(fn) table.insert(AnimWM,  fn); return fn end
local function pumpList(list, t, dt) for i = 1, #list do list[i](t, dt) end end

-- widgets that paint their own colours register a refresher so a theme swap
-- reaches gradients / orbs / rims that applyTheme's simple prop-tween can't see
local ChromeThemeRefresh = {}
local function onThemeRefresh(fn) table.insert(ChromeThemeRefresh, fn); return fn end

-- spring-ish pop (overshoot + settle) for anything that should feel physical
local function spring(o, t, props)
    if not o or not o.Parent then return end
    local ok, tw = pcall(function()
        return TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out), props)
    end)
    if ok and tw then tw:Play() return tw end
end

-- linear two-stop (or ColorSequence) gradient
local function gradient(parent, a, b, rot, trans)
    if not parent then return end
    local g = new("UIGradient", {
        Color = (typeof(a) == "ColorSequence") and a or ColorSequence.new(a, b or a),
        Rotation = rot or 0, Parent = parent,
    })
    if trans then g.Transparency = trans end
    return g
end

-- a border that is itself a gradient — the single biggest "premium" tell
local function gStroke(parent, c1, c2, thick, trans, rot)
    if not parent then return end
    local s = new("UIStroke", {
        Thickness = thick or 1.5, Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
    })
    local g = new("UIGradient", {Color = ColorSequence.new(c1, c2), Rotation = rot or 0, Parent = s})
    return s, g
end

-- soft glow orb built from concentric rounded rings (a procedural radial falloff)
local function orb(parent, color, sizePx)
    local holder = new("Frame", {
        Size = UDim2.new(0, sizePx, 0, sizePx), BackgroundTransparency = 1,
        ZIndex = 0, Parent = parent,
    })
    local rings = {}
    for i = 5, 1, -1 do
        local f = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(i / 5, 0, i / 5, 0), BackgroundColor3 = color,
            BackgroundTransparency = 0.80 + (5 - i) * 0.038, BorderSizePixel = 0,
            ZIndex = 0, Parent = holder,
        })
        corner(f, 9999)
        rings[i] = f
    end
    local function recolor(c) for _, f in ipairs(rings) do f.BackgroundColor3 = c end end
    return holder, recolor
end

--============================================================================--
--  4. SCREEN ROOT
--============================================================================--

local ScreenGui = new("ScreenGui", {
    Name = "MW_" .. tostring(math.random(100000, 999999)),
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999,
})

do
    local parented = false
    if gethui then parented = pcall(function() ScreenGui.Parent = gethui() end) end
    if not parented and syn and syn.protect_gui then
        parented = pcall(function() syn.protect_gui(ScreenGui); ScreenGui.Parent = CoreGui end)
    end
    if not parented then parented = pcall(function() ScreenGui.Parent = CoreGui end) end
    if not parented then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end

local EspRoot   = new("Folder",  {Name = "Esp", Parent = ScreenGui})
-- overlay sits above everything; dropdown menus live here so nothing clips them
local Overlay   = new("Frame", {
    Name = "Overlay", Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1, ZIndex = 5000, Parent = ScreenGui,
})

--============================================================================--
--  5. NOTIFICATIONS
--============================================================================--

local NotifyHolder = new("Frame", {
    AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18),
    Size = UDim2.new(0, 330, 0, 480), BackgroundTransparency = 1, Parent = ScreenGui,
})
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    Padding = UDim.new(0, 8), Parent = NotifyHolder,
})

local function Notify(title, body, dur, kind)
    dur = dur or 3.5
    local tint = (kind == "bad" and C3(255, 70, 90)) or (kind == "warn" and C3(255, 185, 60)) or Theme.Accent

    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Card,
        ClipsDescendants = true, Parent = NotifyHolder,
    })
    corner(card, 11)
    stroke(card, "Stroke", 1)
    gStroke(card, tint, tint:Lerp(C3(255,255,255), 0.4), 1.2, 0.35)

    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 1, -14), Position = UDim2.new(0, 7, 0, 7),
        BackgroundColor3 = tint, BorderSizePixel = 0, Parent = card,
    })
    corner(bar, 3)
    gradient(bar, tint, tint:Lerp(C3(255,255,255), 0.5), 90)

    new("TextLabel", {
        Position = UDim2.new(0, 20, 0, 9), Size = UDim2.new(1, -30, 0, 18),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = tostring(title),
        TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
    })
    new("TextLabel", {
        Position = UDim2.new(0, 20, 0, 28), Size = UDim2.new(1, -30, 0, 30),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = tostring(body),
        TextSize = 12, TextWrapped = true, TextColor3 = Theme.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = card,
    })

    local progress = new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = tint, BorderSizePixel = 0, Parent = card,
    })

    spring(card, 0.4, {Size = UDim2.new(1, 0, 0, 64)})
    tween(progress, dur, {Size = UDim2.new(0, 0, 0, 2)}, Enum.EasingStyle.Linear)

    task.delay(dur, function()
        if not card.Parent then return end
        tween(card, 0.25, {Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1})
        task.wait(0.3)
        if card then card:Destroy() end
    end)
end

--============================================================================--
--  6. WATERMARK
--============================================================================--

local Watermark = new("Frame", {
    Position = UDim2.new(0, 18, 0, 18), Size = UDim2.new(0, 320, 0, 34),
    BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.08, Parent = ScreenGui,
})
corner(Watermark, 11)
themed(Watermark, "BackgroundColor3", "Panel")
do
    local _, g = gStroke(Watermark, Theme.Accent, Theme.Accent2, 1.4, 0.12)
    animateWM(function(t) g.Rotation = (t * 55) % 360 end)
    onThemeRefresh(function() g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
end

-- top-light glass sheen
local WmGlass = new("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C3(255,255,255), BorderSizePixel = 0, Parent = Watermark})
corner(WmGlass, 11)
gradient(WmGlass, C3(255,255,255), C3(255,255,255), 90,
    NumberSequence.new({NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 1)}))

-- breathing status core
local WmDot = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
    Size = UDim2.new(0, 8, 0, 8), BackgroundColor3 = C3(90, 230, 140), BorderSizePixel = 0, Parent = Watermark,
})
corner(WmDot, 4)
local WmDotGlow = new("UIStroke", {Thickness = 3, Color = C3(90, 230, 140), Transparency = 0.4, Parent = WmDot})
animateWM(function(t)
    local k = (math.sin(t * 3) + 1) / 2
    WmDot.Size = UDim2.new(0, 7 + k * 3, 0, 7 + k * 3)
    WmDotGlow.Transparency = 0.25 + k * 0.55
end)

-- shimmering wordmark
local WmLogo = new("TextLabel", {
    Position = UDim2.new(0, 30, 0, 0), Size = UDim2.new(0, 96, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 13.5,
    TextXAlignment = Enum.TextXAlignment.Left, Text = "MONEYWARE", TextColor3 = C3(255,255,255), Parent = Watermark,
})
do
    local lg = gradient(WmLogo, Theme.Accent, Theme.Accent2, 0)
    animateWM(function(t) lg.Offset = Vector2.new((t * 0.22) % 2 - 1, 0) end)
    onThemeRefresh(function() lg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
end

-- monospace telemetry (fps / ping / alive / state) — a real HUD readout
local WmText = new("TextLabel", {
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(1, -134, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11.5,
    TextXAlignment = Enum.TextXAlignment.Right, Text = "booting", Parent = Watermark,
})
themed(WmText, "TextColor3", "Sub")

--============================================================================--
--  7. MAIN WINDOW
--============================================================================--

local WIN_W, WIN_H = 940, 600

local Main = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, WIN_W, 0, WIN_H), BackgroundColor3 = Theme.Bg,
    ClipsDescendants = true, Parent = ScreenGui,
})
corner(Main, 16)
themed(Main, "BackgroundColor3", "Bg")

--[[ LIVING BACKDROP — an aurora of drifting light ribbons over a field of
     twinkling stardust, all procedural (zero asset ids). Registered on AnimWin,
     so it ONLY moves while the menu is on screen — a closed menu costs nothing. ]]
local Backdrop = new("Frame", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    ClipsDescendants = true, ZIndex = 0, Parent = Main,
})
corner(Backdrop, 16)

-- three overlapping aurora ribbons. IMPORTANT: the frames are NOT rotated —
-- Roblox's ClipsDescendants ignores rotated children, so a rotated frame would
-- spill out of the window into the game. Instead the frames stay axis-aligned
-- (fully clipped) and the light is angled + animated via the GRADIENT inside.
local ribbonDefs = {
    {key = "Accent",  h = 0.55, y = 0.18, sp = 0.055, rot = 20},
    {key = "Accent2", h = 0.62, y = 0.52, sp = -0.04, rot = -16},
    {key = "Accent",  h = 0.48, y = 0.82, sp = 0.03,  rot = 28},
}
local ribbons = {}
for idx, d in ipairs(ribbonDefs) do
    local f = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, d.y, 0),
        Size = UDim2.new(1.2, 0, d.h, 0), BackgroundColor3 = Theme[d.key],
        BorderSizePixel = 0, ZIndex = 0, Parent = Backdrop,          -- no frame Rotation on purpose
    })
    local g = new("UIGradient", {Rotation = d.rot, Parent = f})       -- angle the band via the gradient
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.85), NumberSequenceKeypoint.new(1, 1)})
    ribbons[idx] = {f = f, g = g, d = d}
end
animate(function(t)
    for _, rb in ipairs(ribbons) do
        local d = rb.d
        rb.g.Rotation = d.rot + math.sin(t * d.sp * 1.6) * 10          -- band angle sways
        rb.g.Offset   = Vector2.new(math.sin(t * d.sp * 2.2) * 0.4, 0) -- band slides across -> flow
        rb.f.Position = UDim2.new(0.5, 0, d.y, math.cos(t * d.sp * 0.8) * 14)  -- gentle vertical drift only
    end
end)
onThemeRefresh(function()
    for _, rb in ipairs(ribbons) do rb.f.BackgroundColor3 = Theme[rb.d.key] end
end)

-- a field of stardust motes drifting slowly upward, each twinkling on its own phase
local motes = {}
for i = 1, 14 do
    local sz = 2 + math.random() * 2.5
    local m = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(math.random(), 0, math.random(), 0),
        Size = UDim2.new(0, sz, 0, sz), BackgroundColor3 = C3(255, 255, 255),
        BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 0, Parent = Backdrop,
    })
    corner(m, 2)
    motes[i] = {f = m, x = math.random(), y = math.random(), sp = 0.012 + math.random() * 0.022, ph = math.random() * 6.283}
end
animate(function(t)
    for _, mo in ipairs(motes) do
        local ny = (mo.y - t * mo.sp) % 1
        mo.f.Position = UDim2.new(math.clamp(mo.x + math.sin(t * 0.3 + mo.ph) * 0.02, 0, 1), 0, ny, 0)
        mo.f.BackgroundTransparency = 0.4 + (math.sin(t * 1.4 + mo.ph) + 1) * 0.28
    end
end)

-- faint top-light glass sheen over the aurora
local Sheen = new("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C3(255,255,255), BorderSizePixel = 0, ZIndex = 0, Parent = Backdrop})
gradient(Sheen, C3(255,255,255), C3(255,255,255), 90,
    NumberSequence.new({NumberSequenceKeypoint.new(0, 0.92), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.98)}))

-- rotating gradient rim: the halo edge that reads as "expensive"
local MainStroke, mainRimGrad = gStroke(Main, Theme.Accent, Theme.Accent2, 1.6, 0.25)
animate(function(t) mainRimGrad.Rotation = (t * 18) % 360 end)
onThemeRefresh(function() mainRimGrad.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)

local UIScaler = new("UIScale", {Scale = Config.UIScale, Parent = Main})

local TitleBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.15,
    BorderSizePixel = 0, Parent = Main,
})
themed(TitleBar, "BackgroundColor3", "Panel")

-- pulsing status core
local TitleDot = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0),
    Size = UDim2.new(0, 9, 0, 9), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = TitleBar,
})
corner(TitleDot, 5); themed(TitleDot, "BackgroundColor3", "Accent")
local TitleDotGlow = new("UIStroke", {Thickness = 3.5, Color = Theme.Accent, Transparency = 0.4, Parent = TitleDot})
themed(TitleDotGlow, "Color", "Accent")
animate(function(t)
    local k = (math.sin(t * 2.4) + 1) / 2
    TitleDot.Size = UDim2.new(0, 8 + k * 3, 0, 8 + k * 3)
    TitleDotGlow.Transparency = 0.2 + k * 0.55
end)

local Logo = new("TextLabel", {
    Position = UDim2.new(0, 40, 0, 0), Size = UDim2.new(0, 140, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 19,
    Text = "MONEYWARE", TextColor3 = C3(255,255,255), TextXAlignment = Enum.TextXAlignment.Left, Parent = TitleBar,
})
do
    local lg = gradient(Logo, Theme.Accent, Theme.Accent2, 0)
    animate(function(t) lg.Offset = Vector2.new((t * 0.28) % 2 - 1, 0) end)
    onThemeRefresh(function() lg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
end

-- version chip
local VerChip = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 190, 0.5, 0), Size = UDim2.new(0, 42, 0, 20),
    BackgroundColor3 = Theme.Card, Parent = TitleBar,
})
corner(VerChip, 6); themed(VerChip, "BackgroundColor3", "Card")
do local _, g = gStroke(VerChip, Theme.Accent, Theme.Accent2, 1, 0.25)
   onThemeRefresh(function() g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end) end
local VerText = new("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
    Text = "v2.0", TextColor3 = C3(255,255,255), Parent = VerChip,
})
do local vg = gradient(VerText, Theme.Accent, Theme.Accent2, 0)
   onThemeRefresh(function() vg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end) end

local SubTitle = new("TextLabel", {
    Position = UDim2.new(0, 244, 0, 0), Size = UDim2.new(0, 260, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
    Text = "da hood // zee hood", TextXAlignment = Enum.TextXAlignment.Left, Parent = TitleBar,
})
themed(SubTitle, "TextColor3", "Sub")

-- animated underline sweep along the title bar's base
local TitleLine = new("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1.5),
    BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = TitleBar,
})
do
    local tg = gradient(TitleLine, ColorSequence.new(Theme.Accent, Theme.Accent2), nil, 0)
    tg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1)})
    animate(function(t) tg.Offset = Vector2.new((t * 0.35) % 2 - 1, 0) end)
    onThemeRefresh(function() tg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
end

local CloseBtn = new("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
    Size = UDim2.new(0, 28, 0, 28), BackgroundColor3 = Theme.Card, AutoButtonColor = false,
    Font = Enum.Font.GothamBold, Text = "×", TextSize = 12, Parent = TitleBar,
})
corner(CloseBtn, 8); stroke(CloseBtn, "Stroke", 1)
themed(CloseBtn, "TextColor3", "Sub")

local MinBtn = new("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0),
    Size = UDim2.new(0, 28, 0, 28), BackgroundColor3 = Theme.Card, AutoButtonColor = false,
    Font = Enum.Font.GothamBold, Text = "—", TextSize = 13, Parent = TitleBar,
})
corner(MinBtn, 8); stroke(MinBtn, "Stroke", 1)
themed(MinBtn, "BackgroundColor3", "Card"); themed(MinBtn, "TextColor3", "Sub")

local Sidebar = new("Frame", {
    Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(0, 194, 1, -52),
    BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.12, BorderSizePixel = 0, Parent = Main,
})
themed(Sidebar, "BackgroundColor3", "Panel")

-- gradient divider down the sidebar's right edge
local SideEdge = new("Frame", {
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1.5, 1, 0),
    BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = Sidebar,
})
do
    local eg = gradient(SideEdge, ColorSequence.new(Theme.Accent, Theme.Accent2), nil, 90)
    eg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0.85)})
    onThemeRefresh(function() eg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
end

-- the single morphing selector — slides to the active tab, drawn BEHIND the buttons
local TabIndicator = new("Frame", {
    Position = UDim2.new(0, 12, 0, 14), Size = UDim2.new(1, -24, 0, 38),
    BackgroundColor3 = Theme.Card, BorderSizePixel = 0, Visible = false, ZIndex = 0, Parent = Sidebar,
})
corner(TabIndicator, 10); themed(TabIndicator, "BackgroundColor3", "Card")
do
    local _, ig = gStroke(TabIndicator, Theme.Accent, Theme.Accent2, 1.3, 0.25)
    animate(function(t) ig.Rotation = (t * 45) % 360 end)
    onThemeRefresh(function() ig.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
end
local TabIndBar = new("Frame", {
    Position = UDim2.new(0, 0, 0.5, -9), Size = UDim2.new(0, 3, 0, 18),
    BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, ZIndex = 1, Parent = TabIndicator,
})
corner(TabIndBar, 2); themed(TabIndBar, "BackgroundColor3", "Accent")

local TabHolder = new("Frame", {
    Position = UDim2.new(0, 12, 0, 14), Size = UDim2.new(1, -24, 1, -80),
    BackgroundTransparency = 1, Parent = Sidebar,
})
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = TabHolder})

-- deterministic vertical cursor so the indicator lands exactly on each tab,
-- independent of UIScale (offsets scale uniformly with the indicator)
local TabLayoutY = 14

local UserCard = new("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12),
    Size = UDim2.new(1, -24, 0, 50), BackgroundColor3 = Theme.Card, Parent = Sidebar,
})
corner(UserCard, 9); stroke(UserCard, "Stroke", 1)
themed(UserCard, "BackgroundColor3", "Card")

local UserPfp = new("ImageLabel", {
    Position = UDim2.new(0, 8, 0.5, -16), Size = UDim2.new(0, 32, 0, 32),
    BackgroundColor3 = Theme.Panel,
    Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150",
    Parent = UserCard,
})
corner(UserPfp, 16)

local UserName = new("TextLabel", {
    Position = UDim2.new(0, 48, 0, 9), Size = UDim2.new(1, -56, 0, 15),
    BackgroundTransparency = 1, Font = Enum.Font.GothamSemibold, TextSize = 12,
    Text = LocalPlayer.DisplayName, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = UserCard,
})
themed(UserName, "TextColor3", "Text")

local UserStat = new("TextLabel", {
    Position = UDim2.new(0, 48, 0, 25), Size = UDim2.new(1, -56, 0, 14),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
    Text = "connected", TextXAlignment = Enum.TextXAlignment.Left, Parent = UserCard,
})
themed(UserStat, "TextColor3", "Sub")

local PageHolder = new("Frame", {
    Position = UDim2.new(0, 194, 0, 52), Size = UDim2.new(1, -194, 1, -52),
    BackgroundTransparency = 1, ClipsDescendants = true, Parent = Main,
})

--============================================================================--
--  8. SHARED INPUT ROUTER  (one connection, not one per widget)
--============================================================================--

local DragTargets  = {}   -- active drag handlers
local CloseMenus   = {}   -- open dropdown closers

local function closeAllMenus(except)
    for fn, tag in pairs(CloseMenus) do
        if tag ~= except then fn() end
    end
end

bind(UserInputService.InputChanged, function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
    for fn in pairs(DragTargets) do fn(i) end
end)

local ReleaseCallbacks = {}
bind(UserInputService.InputEnded, function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 and i.UserInputType ~= Enum.UserInputType.Touch then return end
    table.clear(DragTargets)
    for _, cb in ipairs(ReleaseCallbacks) do pcall(cb) end
end)

-- window drag
do
    local dragStart, startPos
    local function move(i)
        if not dragStart then return end
        local d = i.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
    bind(TitleBar.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart, startPos = i.Position, Main.Position
            closeAllMenus()
            DragTargets[move] = true
        end
    end)
    table.insert(ReleaseCallbacks, function() dragStart = nil end)
end

--============================================================================--
--  9. UI LIBRARY
--============================================================================--

local UI = {}
local Tabs, CurrentTab = {}, nil

-- small caps divider that groups tabs into COMBAT / VISUALS / SYSTEM
function UI.TabCategory(name)
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        TextSize = 10, Text = "  " .. string.upper(name), TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Bottom, Parent = TabHolder,
    })
    themed(lbl, "TextColor3", "Sub")
    TabLayoutY = TabLayoutY + 22 + 6
    return lbl
end

function UI.Tab(name, icon)
    local myY = TabLayoutY
    TabLayoutY = TabLayoutY + 38 + 6

    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = TabHolder,
    })
    corner(btn, 10)

    -- glyph chip
    local ic = new("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0, 26, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14,
        Text = icon or "•", Parent = btn,
    })
    themed(ic, "TextColor3", "Sub")

    local lbl = new("TextLabel", {
        Position = UDim2.new(0, 44, 0, 0), Size = UDim2.new(1, -52, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamSemibold, TextSize = 13,
        Text = name, TextXAlignment = Enum.TextXAlignment.Left, Parent = btn,
    })
    themed(lbl, "TextColor3", "Sub")

    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false,
        ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0, Parent = PageHolder,
    })
    themed(page, "ScrollBarImageColor3", "Accent")
    pad(page, 22, 22, 20, 26)
    new("UIListLayout", {Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page})

    local tabObj = {Name = name, Button = btn, Page = page, Body = page, Icon = ic, Label = lbl, Y = myY}

    local function select()
        closeAllMenus()
        for _, t in ipairs(Tabs) do
            t.Page.Visible = false
            tween(t.Icon,  0.18, {TextColor3 = Theme.Sub})
            tween(t.Label, 0.18, {TextColor3 = Theme.Sub})
        end
        CurrentTab = tabObj

        -- slide the shared selector onto this tab
        TabIndicator.Visible = true
        tween(TabIndicator, 0.32, {Position = UDim2.new(0, 12, 0, myY)}, Enum.EasingStyle.Quint)

        tween(ic,  0.2, {TextColor3 = Theme.Accent})
        tween(lbl, 0.2, {TextColor3 = Theme.Text})

        -- content rise-in
        page.Visible = true
        page.Position = UDim2.new(0, 0, 0, 8)
        tween(page, 0.26, {Position = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Quint)
    end

    btn.MouseButton1Click:Connect(select)
    btn.MouseEnter:Connect(function() if CurrentTab ~= tabObj then tween(lbl, 0.15, {TextColor3 = Theme.Text}); tween(ic, 0.15, {TextColor3 = Theme.Text}) end end)
    btn.MouseLeave:Connect(function() if CurrentTab ~= tabObj then tween(lbl, 0.15, {TextColor3 = Theme.Sub}); tween(ic, 0.15, {TextColor3 = Theme.Sub}) end end)

    tabObj.Select = select
    table.insert(Tabs, tabObj)
    if #Tabs == 1 then select() end
    return tabObj
end

function UI.Section(tab, title, desc)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.04, Parent = tab.Body,
    })
    corner(holder, 12); stroke(holder, "Stroke", 1)
    themed(holder, "BackgroundColor3", "Panel")
    pad(holder, 16, 16, 14, 16)
    new("UIListLayout", {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder})

    local head = new("Frame", {Size = UDim2.new(1, 0, 0, desc and 36 or 20), BackgroundTransparency = 1, Parent = holder})

    -- gradient accent bar beside the title
    local bar = new("Frame", {
        Position = UDim2.new(0, 0, 0, 2), Size = UDim2.new(0, 3, 0, desc and 32 or 15),
        BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = head,
    })
    corner(bar, 2)
    do
        local bg = gradient(bar, Theme.Accent, Theme.Accent2, 90)
        onThemeRefresh(function() bg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
    end

    local t = new("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -12, 0, 18), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13.5, Text = title, TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
    })
    themed(t, "TextColor3", "Text")
    if desc then
        local d = new("TextLabel", {
            Position = UDim2.new(0, 12, 0, 18), Size = UDim2.new(1, -12, 0, 16),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, Text = desc,
            TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = head,
        })
        themed(d, "TextColor3", "Sub")
    end
    return holder
end

local function rowBase(parent, h)
    local row = new("Frame", {Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Card, Parent = parent})
    corner(row, 8); themed(row, "BackgroundColor3", "Card")
    return row
end

-- Toggle --------------------------------------------------------------------
function UI.Toggle(parent, text, default, callback)
    local row = rowBase(parent, 38)
    local lbl = new("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -70, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12.5, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    themed(lbl, "TextColor3", "Text")

    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0, 42, 0, 21), BackgroundColor3 = Theme.Stroke, Parent = row,
    })
    corner(track, 11)
    -- accent glow that lights up while on
    local glow = new("UIStroke", {Thickness = 2.5, Color = Theme.Accent, Transparency = 1, Parent = track})
    themed(glow, "Color", "Accent")
    local trackGrad = gradient(track, Theme.Accent, Theme.Accent2, 0, NumberSequence.new(1))
    local knob = new("Frame", {
        Position = UDim2.new(0, 3, 0.5, -7), Size = UDim2.new(0, 15, 0, 15),
        BackgroundColor3 = Theme.Sub, Parent = track,
    })
    corner(knob, 8)

    local btn = new("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = row})

    local state = default and true or false
    local function render(anim)
        local d = anim and 0.2 or 0.01
        tween(track, d, {BackgroundColor3 = state and Theme.Accent or Theme.Stroke})
        tween(glow,  d, {Transparency = state and 0.15 or 1})
        trackGrad.Transparency = state and NumberSequence.new(0) or NumberSequence.new(1)
        local pos = state and UDim2.new(1, -18, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        if anim then spring(knob, 0.34, {Position = pos}) else knob.Position = pos end
        tween(knob, d, {BackgroundColor3 = state and C3(255, 255, 255) or Theme.Sub})
    end
    render(false)

    btn.MouseButton1Click:Connect(function()
        state = not state
        render(true)
        task.spawn(function()
            local ok, err = pcall(callback, state)
            if not ok then warn("[MoneyWare] toggle '" .. text .. "': " .. tostring(err)) end
        end)
    end)
    btn.MouseEnter:Connect(function() tween(row, 0.15, {BackgroundColor3 = Theme.Card:Lerp(Theme.Stroke, 0.45)}) end)
    btn.MouseLeave:Connect(function() tween(row, 0.15, {BackgroundColor3 = Theme.Card}) end)

    return {Set = function(v) state = v; render(true); task.spawn(pcall, callback, state) end, Get = function() return state end}
end

-- Slider --------------------------------------------------------------------
function UI.Slider(parent, text, min, max, default, decimals, suffix, callback)
    local row = rowBase(parent, 50)
    local lbl = new("TextLabel", {
        Position = UDim2.new(0, 12, 0, 7), Size = UDim2.new(1, -90, 0, 16),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12.5, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    themed(lbl, "TextColor3", "Text")

    local val = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7),
        Size = UDim2.new(0, 78, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        TextSize = 12, Text = "", TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
    })
    themed(val, "TextColor3", "Accent")

    local bar = new("Frame", {
        Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = Theme.Stroke, Parent = row,
    })
    corner(bar, 3); themed(bar, "BackgroundColor3", "Stroke")

    local fill = new("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = bar})
    corner(fill, 3)
    local fillGrad = new("UIGradient", {Color = ColorSequence.new(Theme.Accent, Theme.Accent2), Parent = fill})

    local dot = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = C3(255, 255, 255), ZIndex = 3, Parent = bar,
    })
    corner(dot, 6)
    local dotGlow = new("UIStroke", {Thickness = 3, Color = Theme.Accent, Transparency = 0.3, Parent = dot})
    themed(dotGlow, "Color", "Accent")

    local value = default

    local function set(v, fire)
        value = math.clamp(round(v, decimals or 0), min, max)
        local a = (max > min) and (value - min) / (max - min) or 0
        fill.Size = UDim2.new(a, 0, 1, 0)
        dot.Position = UDim2.new(a, 0, 0.5, 0)
        val.Text = tostring(value) .. (suffix or "")
        if fire ~= false then
            local ok, err = pcall(callback, value)
            if not ok then warn("[MoneyWare] slider '" .. text .. "': " .. tostring(err)) end
        end
    end

    local function fromX(x)
        local w = bar.AbsoluteSize.X
        if w <= 0 then return end
        set(min + (max - min) * math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1))
    end

    local function move(i) fromX(i.Position.X) end

    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            fromX(i.Position.X)
            DragTargets[move] = true
            tween(dot, 0.12, {Size = UDim2.new(0, 16, 0, 16)})
        end
    end)
    table.insert(ReleaseCallbacks, function()
        if dot and dot.Parent then tween(dot, 0.12, {Size = UDim2.new(0, 12, 0, 12)}) end
    end)

    set(default, false)
    return {Set = function(v) set(v) end, Get = function() return value end, Grad = fillGrad}
end

-- Dropdown (menu lives on the overlay layer, so it can never be clipped) -----
function UI.Dropdown(parent, text, options, default, callback)
    local row = rowBase(parent, 38)
    local lbl = new("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12.5, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    themed(lbl, "TextColor3", "Text")

    local box = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 150, 0, 26), BackgroundColor3 = Theme.Panel,
        AutoButtonColor = false, Text = "", Parent = row,
    })
    corner(box, 7); stroke(box, "Stroke", 1); themed(box, "BackgroundColor3", "Panel")

    local cur = new("TextLabel", {
        Position = UDim2.new(0, 9, 0, 0), Size = UDim2.new(1, -28, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, Text = tostring(default),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = box,
    })
    themed(cur, "TextColor3", "Sub")

    local arrow = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        TextSize = 9, Text = "v", Parent = box,
    })
    themed(arrow, "TextColor3", "Accent")

    local menu = new("ScrollingFrame", {
        Size = UDim2.new(0, 150, 0, 0), BackgroundColor3 = Theme.Panel, Visible = false,
        ZIndex = 5001, ScrollBarThickness = 2, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = Overlay,
    })
    corner(menu, 7); stroke(menu, "Stroke", 1); themed(menu, "BackgroundColor3", "Panel")
    new("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu})
    pad(menu, 4, 4, 4, 4)

    local open, selected, count = false, default, 0

    local function close()
        if not open then return end
        open = false
        tween(menu, 0.16, {Size = UDim2.new(0, menu.Size.X.Offset, 0, 0)})
        tween(arrow, 0.16, {Rotation = 0})
        task.delay(0.18, function() if not open and menu.Parent then menu.Visible = false end end)
    end
    CloseMenus[close] = menu

    local function build(list)
        for _, c in ipairs(menu:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        count = 0
        for _, opt in ipairs(list) do
            count = count + 1
            local o = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Theme.Card, BackgroundTransparency = 1,
                AutoButtonColor = false, ZIndex = 5002, Font = Enum.Font.Gotham, TextSize = 12,
                Text = "  " .. tostring(opt), TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.Sub, Parent = menu,
            })
            corner(o, 5)
            o.MouseEnter:Connect(function() tween(o, 0.12, {BackgroundTransparency = 0, TextColor3 = Theme.Text}) end)
            o.MouseLeave:Connect(function() tween(o, 0.12, {BackgroundTransparency = 1, TextColor3 = Theme.Sub}) end)
            o.MouseButton1Click:Connect(function()
                selected = opt
                cur.Text = tostring(opt)
                close()
                local ok, err = pcall(callback, opt)
                if not ok then warn("[MoneyWare] dropdown '" .. text .. "': " .. tostring(err)) end
            end)
        end
    end
    build(options)

    box.MouseButton1Click:Connect(function()
        if open then close() return end
        local camera = cam()
        if not camera then return end
        closeAllMenus(menu)
        open = true
        local ap, asz = box.AbsolutePosition, box.AbsoluteSize
        local h = math.min(count * 26 + 8, 170)
        local downSpace = camera.ViewportSize.Y - (ap.Y + asz.Y) - 12
        local y = (downSpace >= h) and (ap.Y + asz.Y + 6) or (ap.Y - h - 6)
        menu.Position = UDim2.new(0, ap.X, 0, y)
        menu.Size = UDim2.new(0, asz.X, 0, 0)
        menu.Visible = true
        tween(menu, 0.2, {Size = UDim2.new(0, asz.X, 0, h)})
        tween(arrow, 0.2, {Rotation = 180})
    end)

    return {
        Set = function(v) selected = v; cur.Text = tostring(v); pcall(callback, v) end,
        Get = function() return selected end,
        Refresh = function(list) build(list) end,
        Close = close,
    }
end

-- Button --------------------------------------------------------------------
function UI.Button(parent, text, callback)
    local row = rowBase(parent, 36)
    -- gradient wash revealed on hover
    local wash = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1,
        BorderSizePixel = 0, Parent = row,
    })
    corner(wash, 8)
    do
        local wg = gradient(wash, Theme.Accent, Theme.Accent2, 0)
        onThemeRefresh(function() wg.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end)
    end
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, TextSize = 12.5, Text = text, Parent = row,
    })
    themed(btn, "TextColor3", "Text")
    btn.MouseEnter:Connect(function()
        tween(wash, 0.16, {BackgroundTransparency = 0}); tween(btn, 0.16, {TextColor3 = C3(255,255,255)})
    end)
    btn.MouseLeave:Connect(function()
        tween(wash, 0.16, {BackgroundTransparency = 1}); tween(btn, 0.16, {TextColor3 = Theme.Text})
    end)
    btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)
        if not ok then warn("[MoneyWare] button '" .. text .. "': " .. tostring(err)) end
    end)
    return row
end

-- Keybind -------------------------------------------------------------------
local KeybindListeners = {}
function UI.Keybind(parent, text, defaultKey, callback)
    local row = rowBase(parent, 38)
    local lbl = new("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -130, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12.5, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    themed(lbl, "TextColor3", "Text")

    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 104, 0, 26), BackgroundColor3 = Theme.Panel, AutoButtonColor = false,
        Font = Enum.Font.GothamSemibold, TextSize = 11.5, Text = defaultKey.Name, Parent = row,
    })
    corner(btn, 7); stroke(btn, "Stroke", 1)
    themed(btn, "BackgroundColor3", "Panel"); themed(btn, "TextColor3", "Accent")

    local listening = false
    btn.MouseButton1Click:Connect(function() listening = true; btn.Text = "press a key" end)
    table.insert(KeybindListeners, function(key)
        if not listening then return false end
        listening = false
        btn.Text = key.Name
        pcall(callback, key)
        return true
    end)
    return btn
end

function UI.Label(parent, text)
    local l = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11.5, Text = text,
        TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
    })
    themed(l, "TextColor3", "Sub")
    return l
end

--============================================================================--
--  10. PLAYER CACHE  (kills FindFirstChild spam)
--============================================================================--

local Cache = {}   -- [player] = {Char, Hum, Root, Head, Fx, KO, HPVal, Died}

--[[ ROOT / HEAD RESOLUTION — never return nil if the character has ANY part.

    Waiting on an exact part name is how players get silently skipped: it can
    lag behind the model, differ by rig, or be renamed. These walk down to
    "literally any BasePart" so there is always something to attach to.
]]
local function getRoot(char)
    if not char then return nil end
    local r = char:FindFirstChild("HumanoidRootPart")
          or char:FindFirstChild("Torso")
          or char:FindFirstChild("UpperTorso")
          or char:FindFirstChild("LowerTorso")
          or char.PrimaryPart
    if r and r:IsA("BasePart") then return r end
    return char:FindFirstChildWhichIsA("BasePart")
end

local function getHead(char)
    if not char then return nil end
    local h = char:FindFirstChild("Head")
    if h and h:IsA("BasePart") then return h end
    return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or getRoot(char)
end

local function buildCache(plr)
    local char = plr.Character
    if not char or not char.Parent then Cache[plr] = nil return nil end

    local entry = {
        Char = char,
        Hum  = char:FindFirstChildOfClass("Humanoid"),
        Root = getRoot(char),
        Head = getHead(char),
    }
    local fx = char:FindFirstChild("BodyEffects")
    if fx then
        entry.KO    = fx:FindFirstChild("K.O") or fx:FindFirstChild("KO")
        entry.HPVal = fx:FindFirstChild("HP")
    end
    Cache[plr] = entry
    return entry
end

--[[ CACHE POISONING FIX

    The old fast path validated only Root. If Head or Humanoid hadn't
    replicated at the moment the entry was first built, the incomplete entry
    was returned FOREVER — updateEsp requires e.Head, so that player's ESP
    stayed off for the entire session. Purely a race on replication order,
    which is exactly why it looked random: worked for some people, never for
    others, same every time you rejoined.

    Every field the entry promises is now validated, so a partial entry
    rebuilds on the next access instead of sticking.
]]
local function getCache(plr)
    local e = Cache[plr]
    if e
    and e.Char == plr.Character and e.Char and e.Char.Parent
    and e.Root and e.Root.Parent
    and e.Head and e.Head.Parent
    and e.Hum  and e.Hum.Parent then
        return e
    end
    return buildCache(plr)
end

--============================================================================--
--  11. WHITELIST
--============================================================================--

local Whitelist = {}

function Whitelist.IsTarget(plr)
    if plr == LocalPlayer then return false end
    if Config.TeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then return false end

    --[[ MODE IS THE FINAL WORD.

        This was the "I picked people but it fights everyone" bug. ForceAll and
        AutoWhitelist used to return true ABOVE this point, so Selected/Blacklist
        never actually restricted anything. Selected and Blacklist are RESTRICTIVE
        by definition, so nothing is allowed to override them. ForceAll /
        AutoWhitelist only ever apply inside "Everyone" mode.
    ]]
    local m = Config.WhitelistMode
    if m == "Selected" then
        return Config.Whitelisted[plr.UserId] == true       -- ONLY the people you picked
    elseif m == "Blacklist" then
        return Config.Blacklisted[plr.UserId] ~= true        -- everyone EXCEPT the ones you picked
    end

    -- "Everyone" mode
    return true
end

function Whitelist.Toggle(plr)
    local t = (Config.WhitelistMode == "Blacklist") and Config.Blacklisted or Config.Whitelisted
    if t[plr.UserId] then t[plr.UserId] = nil return false end
    t[plr.UserId] = true
    return true
end

--============================================================================--
--  12. DEAD CHECK
--============================================================================--

--[[ DEAD CHECK — POSITIVE EVIDENCE ONLY

    The old version returned TRUE (dead) whenever it couldn't resolve the
    Humanoid or HumanoidRootPart. "I don't know" was being treated as "corpse",
    so any player whose parts hadn't resolved on that exact tick was counted as
    down and had their hitbox destroyed. The readout said "N down" and looked
    correct while people silently went uncovered.

    Now: unknown means ALIVE. A player is only dead when something explicitly
    says so. Reads the character directly — never the cache, which can be stale.
]]
local function isDead(plr)
    local char = plr.Character
    if not char or not char.Parent then return false end   -- unknown != dead

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.MaxHealth > 0 and hum.Health <= 0 then return true end

    if Config.KOCheck then
        local fx = char:FindFirstChild("BodyEffects")
        if fx then
            local ko = fx:FindFirstChild("K.O") or fx:FindFirstChild("KO")
            if ko and ko:IsA("BoolValue") and ko.Value == true then return true end
        end
        if char:GetAttribute("Knocked") == true then return true end
    end

    return false   -- default alive
end

--============================================================================--
--  13. HITBOX ENGINE
--============================================================================--

local Hitbox = {
    Cache    = {},   -- [part] = original properties
    Expanded = {},   -- [part] = size we last asked for
    Settle   = {},   -- [part] = tick() until which a tween is still in flight
    Proxy    = {},   -- [player] = our anchored hitbox part
    Stats    = {applied = 0, down = 0, filtered = 0, nopart = 0, nochar = 0, carried = 0, total = 0},
    Missing  = false, -- true when last sweep left anyone uncovered -> fast retry
    Report   = {},    -- [player] = exact status string from the last sweep
    Ghost    = {},    -- [part] = its CanCollide before we ghosted it
    GhostOn  = {},    -- [character] = true while currently ghosted
}
local HitboxStatus   -- UI label, assigned when the Hitbox tab builds
local HitboxReport   -- UI scroller listing every player's exact status

local PART_LIST = {"HumanoidRootPart", "Head", "Torso", "UpperTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}

-- R6 name -> every rig-equivalent worth trying, in order of preference.
-- Without this, picking "Torso" silently skips anyone on an R15 rig.
local PART_FALLBACK = {
    ["HumanoidRootPart"] = {"HumanoidRootPart"},
    ["Head"]             = {"Head"},
    ["Torso"]            = {"Torso", "UpperTorso", "LowerTorso"},
    ["UpperTorso"]       = {"UpperTorso", "Torso"},
    ["Left Arm"]         = {"Left Arm",  "LeftUpperArm",  "LeftLowerArm",  "LeftHand"},
    ["Right Arm"]        = {"Right Arm", "RightUpperArm", "RightLowerArm", "RightHand"},
    ["Left Leg"]         = {"Left Leg",  "LeftUpperLeg",  "LeftLowerLeg",  "LeftFoot"},
    ["Right Leg"]        = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"},
}

local function resolvePart(char, name)
    local chain = PART_FALLBACK[name]
    if chain then
        for _, n in ipairs(chain) do
            local p = char:FindFirstChild(n)
            if p and p:IsA("BasePart") then return p end
        end
    end

    local direct = char:FindFirstChild(name)
    if direct and direct:IsA("BasePart") then return direct end

    -- last resort: never silently skip a player
    if Config.PartFallback then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then return root end
    end
    return nil
end

local function cachePart(part)
    if Hitbox.Cache[part] then return end
    Hitbox.Cache[part] = {
        Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide,
        Material = part.Material, Color = part.Color, Massless = part.Massless,
        CanTouch = part.CanTouch,
    }
end

local function restorePart(part)
    local c = Hitbox.Cache[part]
    if not c or not part or not part.Parent then return end
    Hitbox.Expanded[part] = nil
    Hitbox.Settle[part] = nil
    pcall(function()
        part.Size = c.Size
        part.Transparency = c.Transparency
        part.CanCollide = c.CanCollide
        part.CanTouch = c.CanTouch
        part.Material = c.Material
        part.Color = c.Color
        part.Massless = c.Massless
    end)
end

--[[ PROXY HITBOX

    Resizing a target's HumanoidRootPart is unwinnable for collision: the
    Humanoid's state machine runs INSIDE the physics step, after every Stepped
    handler, and re-asserts CanCollide = true. Nothing scheduled from Lua gets
    the last word before the solver reads it.

    So we don't touch their part. We build our own:

      Anchored  = true   never joins their assembly — can't push, can't recompute
      CanCollide= false  ours, nothing re-flags it, stays false permanently
      CanQuery  = true   raycasts land on the full expanded volume
      Parent    = their Character model

    Da Hood resolves a shot by walking hit.Parent to find a Humanoid. Our part
    lives in that model, so hit registration is identical while their real root
    part is left completely untouched.
]]
local function destroyProxy(plr)
    local p = Hitbox.Proxy[plr]
    if p then
        Hitbox.Proxy[plr] = nil
        pcall(function() p:Destroy() end)
    end
end

local function destroyAllProxies()
    local snapshot = {}
    for plr in pairs(Hitbox.Proxy) do table.insert(snapshot, plr) end
    for _, plr in ipairs(snapshot) do destroyProxy(plr) end
    table.clear(Hitbox.Proxy)
end

local function getProxy(plr, char)
    local p = Hitbox.Proxy[plr]
    if p and p.Parent == char then return p end
    if p then destroyProxy(plr) end

    local root = getRoot(char)
    if not root then return nil end

    local ok, part = pcall(function()
        local x = Instance.new("Part")
        x.Name          = Config.ProxyName
        x.Anchored      = false   -- THE FREEZE FIX: an anchored part pins their
                                  -- whole assembly (walking in place). Unanchored
                                  -- + welded + massless follows them with no pull.
        x.CanCollide    = false
        x.CanTouch      = false
        x.CanQuery      = true
        x.Massless      = true
        x.CastShadow    = false
        x.TopSurface    = Enum.SurfaceType.Smooth
        x.BottomSurface = Enum.SurfaceType.Smooth
        x.Size          = Vector3.new(Config.HitboxSize, Config.HitboxSize, Config.HitboxSize)
        x.Transparency  = Config.HitboxTrans
        x.Material      = Enum.Material.ForceField
        x.Color         = Config.HitboxColor
        x.LocalTransparencyModifier = 0
        x.CFrame        = root.CFrame
        x.Parent        = char

        -- weld to their real root: tracks them 1:1, never anchors the assembly
        local weld = Instance.new("WeldConstraint")
        weld.Name = "MWWeld"
        weld:SetAttribute("MWProxyWeld", true)
        weld.Part0 = x
        weld.Part1 = root
        weld.Parent = x
        return x
    end)

    -- verify it actually stuck. A game that sanitises foreign children can
    -- reject the parent assignment, and a half-created part must not be cached.
    if not ok or not part or part.Parent ~= char then
        if part then pcall(function() part:Destroy() end) end
        return nil
    end

    Hitbox.Proxy[plr] = part
    return part
end

-- runs on RenderStepped: one CFrame write per target, on parts we own
local function updateProxies()
    if not Config.HitboxEnabled or Config.HitboxMode ~= "Proxy" then return end
    for plr, part in pairs(Hitbox.Proxy) do
        if part.Parent then
            -- collision cleared here too. RenderStepped runs before Stepped, so
            -- between the two passes there is no frame where a proxy is solid.
            if part.CanCollide then part.CanCollide = false end
            if not part.CanQuery then part.CanQuery = true end
            -- keep it locked at full size every frame (same reason as Resize)
            local psz = Config.HitboxSize
            if math.abs(part.Size.X - psz) > 0.05 then part.Size = Vector3.new(psz, psz, psz) end
            if part.LocalTransparencyModifier ~= 0 then part.LocalTransparencyModifier = 0 end

            -- welded, so it tracks the player itself; only hand-place it as a
            -- fallback when the weld is missing (never fight the constraint)
            if not part:FindFirstChild("MWWeld") then
                local char = part.Parent
                local root = (char:FindFirstChild("HumanoidRootPart")
                           or char:FindFirstChild("Torso")
                           or char:FindFirstChild("UpperTorso"))
                if not root then
                    local e = Cache[plr]
                    root = e and e.Root
                end
                if root and root.Parent then
                    part.CFrame = root.CFrame
                end
            end
        else
            Hitbox.Proxy[plr] = nil
        end
    end
end

--[[ GHOST DOWNED BODIES (opt-in)

    Separate from the hitbox: this is the target's own ragdoll geometry. When
    somebody is knocked, Da Hood makes their limbs collidable so the body
    settles on the floor — and then you trip over the corpse.

    CanCollide is collision filtering only; unlike Massless, Material or Size
    it does NOT trigger a mass-property recompute, so this is safe to apply to
    a remote character. Values are cached and restored on revive.
]]
local function ghostCharacter(char)
    if Hitbox.GhostOn[char] then return end
    Hitbox.GhostOn[char] = true
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") and d.CanCollide then
            if Hitbox.Ghost[d] == nil then Hitbox.Ghost[d] = d.CanCollide end
            pcall(function() d.CanCollide = false end)
        end
    end
end

local function unghostCharacter(char)
    if not Hitbox.GhostOn[char] then return end
    Hitbox.GhostOn[char] = nil
    for _, d in ipairs(char:GetDescendants()) do
        local was = Hitbox.Ghost[d]
        if was ~= nil then
            pcall(function() d.CanCollide = was end)
            Hitbox.Ghost[d] = nil
        end
    end
end

local function unghostAll()
    local chars = {}
    for c in pairs(Hitbox.GhostOn) do table.insert(chars, c) end
    for _, c in ipairs(chars) do
        if c and c.Parent then unghostCharacter(c) end
    end
    -- anything whose model already went away
    for part, was in pairs(Hitbox.Ghost) do
        if part and part.Parent then pcall(function() part.CanCollide = was end) end
    end
    table.clear(Hitbox.Ghost)
    table.clear(Hitbox.GhostOn)
end

local function restoreAll()
    local snapshot = {}
    for part in pairs(Hitbox.Cache) do table.insert(snapshot, part) end
    for _, part in ipairs(snapshot) do restorePart(part) end
    table.clear(Hitbox.Cache)
    table.clear(Hitbox.Expanded)
    table.clear(Hitbox.Settle)
    destroyAllProxies()
    unghostAll()
end

local function applyHitbox(plr)
    --[[ EXHAUSTIVE CLASSIFICATION

        Every player reaching this function lands in exactly one bucket and is
        always counted. There is no path that skips a player without recording
        why — if the readout says 40/40, it is genuinely 40 out of 40.
    ]]
    local st = Hitbox.Stats
    st.total = st.total + 1

    local char = plr.Character
    if not char or not char.Parent then
        st.nochar = st.nochar + 1
        Hitbox.Report[plr] = "no character"
        Hitbox.Missing = true      -- triggers a fast retry sweep
        destroyProxy(plr)
        return
    end

    -- ghost/unghost their real ragdoll geometry regardless of hitbox mode
    if Config.GhostDowned then
        if isDead(plr) then ghostCharacter(char) else unghostCharacter(char) end
    elseif Hitbox.GhostOn[char] then
        unghostCharacter(char)
    end

    ------------------------------------------------------------------ PROXY
    if Config.HitboxMode == "Proxy" then
        if not Whitelist.IsTarget(plr) then
            st.filtered = st.filtered + 1
            Hitbox.Report[plr] = "filtered"
            destroyProxy(plr)
            return
        end
        if Config.DeadCheck and isDead(plr) then
            st.down = st.down + 1
            Hitbox.Report[plr] = Config.GhostDowned and "down · ghosted" or "down"
            destroyProxy(plr)
            return
        end

        -- resolved straight off the character, NOT the cache: a stale or
        -- half-built cache entry must never cost someone their hitbox
        local root = getRoot(char)
        if not root then
            st.nopart = st.nopart + 1
            Hitbox.Report[plr] = "no basepart"
            Hitbox.Missing = true
            return
        end

        --[[ CARRY DETECTION

            Da Hood's grab welds the victim's character to the carrier, making
            them one physics assembly. Roblox anchors an ENTIRE assembly if any
            single part in it is anchored — so our anchored proxy becomes the
            assembly root and pins both players until the grab ends.

            AssemblyRootPart tells us the truth directly: if the character's
            root reports an assembly root living outside that character, they
            are welded to somebody else. Drop the proxy for the duration and
            rebuild it automatically on release.
        ]]
        if Config.ReleaseOnGrab then
            local ar
            pcall(function() ar = root.AssemblyRootPart end)
            if ar and ar ~= root and not ar:IsDescendantOf(char) then
                st.carried = st.carried + 1
                Hitbox.Report[plr] = "carried"
                destroyProxy(plr)
                return
            end
        end

        local p = getProxy(plr, char)
        if not p then
            st.nopart = st.nopart + 1
            Hitbox.Report[plr] = "parent rejected"
            Hitbox.Missing = true
            return
        end

        --[[ JOINT GUARD

            Second line of defence. If the game's weld loop grabbed our proxy
            before the carry check saw it, BasePart:GetJoints() returns every
            joint touching this part — cut them all. An unjointed part cannot
            be in anyone's assembly, so it cannot anchor anything.
        ]]
        local cut = 0
        if Config.JointGuard then
            local okJ, joints = pcall(function() return p:GetJoints() end)
            if okJ and joints and #joints > 0 then
                for _, j in ipairs(joints) do
                    if not j:GetAttribute("MWProxyWeld") then   -- never cut OUR weld
                        pcall(function() j:Destroy() end)
                        cut = cut + 1
                    end
                end
            end
        end

        -- keep our weld alive. If JointGuard or the game cut it, the unanchored
        -- proxy would drift off the player — so re-weld it to the current root.
        if not p:FindFirstChild("MWWeld") then
            local wroot = getRoot(char)
            if wroot then
                pcall(function()
                    p.CFrame = wroot.CFrame
                    local weld = Instance.new("WeldConstraint")
                    weld.Name = "MWWeld"
                    weld:SetAttribute("MWProxyWeld", true)
                    weld.Part0 = p
                    weld.Part1 = wroot
                    weld.Parent = p
                end)
            end
        end

        local s = Config.HitboxSize
        local ok = pcall(function()
            if p.Size.X ~= s then p.Size = Vector3.new(s, s, s) end
            if math.abs(p.Transparency - Config.HitboxTrans) > 0.001 then
                p.Transparency = Config.HitboxTrans
            end
            local mat = Enum.Material[Config.HitboxMaterial] or Enum.Material.ForceField
            if p.Material ~= mat then p.Material = mat end
            local col = Config.EspRainbow and Color3.fromHSV((tick() * 0.2) % 1, 0.8, 1) or Config.HitboxColor
            if p.Color ~= col then p.Color = col end
            if p.CanCollide then p.CanCollide = false end
            if not p.CanQuery then p.CanQuery = true end
            -- games that hide characters (first-person, invis states) drive this
            -- separately from Transparency; without resetting it the cube is
            -- there and functional but invisible for exactly those players
            if p.LocalTransparencyModifier ~= 0 then p.LocalTransparencyModifier = 0 end
            if not p:FindFirstChild("MWWeld") then p.CFrame = root.CFrame end
        end)

        if ok then
            st.applied = st.applied + 1
            Hitbox.Report[plr] = (cut > 0) and ("covered · " .. cut .. " joint cut") or "covered"
        else
            st.nopart = st.nopart + 1
            Hitbox.Report[plr] = "write failed"
            Hitbox.Missing = true
            destroyProxy(plr)   -- rebuild from scratch next sweep
        end
        return
    end

    ----------------------------------------------------------------- RESIZE
    local part = resolvePart(char, Config.HitboxPart)
    if not part then
        st.nopart = st.nopart + 1
        Hitbox.Report[plr] = "no '" .. Config.HitboxPart .. "'"
        Hitbox.Missing = true
        return
    end

    cachePart(part)

    if not Whitelist.IsTarget(plr) then
        st.filtered = st.filtered + 1
        Hitbox.Report[plr] = "filtered"
        if Hitbox.Expanded[part] then restorePart(part) end
        return
    end
    if Config.DeadCheck and isDead(plr) then
        st.down = st.down + 1
        Hitbox.Report[plr] = "down"
        if Hitbox.Expanded[part] then restorePart(part) end
        return
    end

    local s = Config.HitboxSize
    local target = Vector3.new(s, s, s)
    local memo = Hitbox.Expanded[part]   -- distinct from `st` (the stats table)

    --[[ DRIFT DETECTION

        Never trust the memo alone. The server, the game's own scripts, or a
        streaming pass can reset Size behind our back. When that happens the
        memo still reads "expanded" and the part would stay normal forever —
        that's the "works on everyone except a few people" symptom.

        Reading .Size is free; compare it to the goal and re-apply on drift.
        While a smooth tween is mid-flight the size is legitimately wrong, so
        that window is excluded to avoid re-firing the tween every tick.
    ]]
    local settling = (Hitbox.Settle[part] or 0) > tick()
    local drifted  = (not settling) and (part.Size - target).Magnitude > 0.35

    pcall(function()
        --[[ WRITE-IF-DIFFERENT ON EVERY PROPERTY.

            Massless and Material each trigger a mass-property recompute on the
            character's physics assembly. Writing them unconditionally 10x/sec
            on every remote player rebuilds those assemblies constantly, which
            stalls the application of their replicated CFrames — the whole
            server appears to freeze in place.

            Guarded, these are written exactly once when a hitbox is first
            applied and never touched again. Steady state = zero physics churn.
        ]]
        local wantCollide = (not Config.PhaseThrough) and Config.HitboxCollide or false
        if part.CanCollide ~= wantCollide then part.CanCollide = wantCollide end
        if Config.NoTouch and part.CanTouch then part.CanTouch = false end
        -- DAMAGE-CRITICAL: raycasts (bullets) only register on a part when CanQuery
        -- is true. Something in the game (or a prior Proxy run) can flip it off, so
        -- re-assert it every apply. Without this, an expanded part is invisible to
        -- the gun's raycast and shots silently pass through -> "hitbox but no damage".
        if not part.CanQuery then part.CanQuery = true end

        -- physics-affecting: skipped entirely in Low Impact mode
        if not Config.LowImpact then
            if part.Massless ~= Config.HitboxMassless then
                part.Massless = Config.HitboxMassless
            end
            local mat = Enum.Material[Config.HitboxMaterial] or Enum.Material.ForceField
            if part.Material ~= mat then part.Material = mat end
        end

        -- render-only, but still guarded
        if math.abs(part.Transparency - Config.HitboxTrans) > 0.001 then
            part.Transparency = Config.HitboxTrans
        end
        local col = Config.EspRainbow and Color3.fromHSV((tick() * 0.2) % 1, 0.8, 1) or Config.HitboxColor
        if part.Color ~= col then part.Color = col end

        -- re-apply on goal change OR on drift
        if not memo or memo ~= s or drifted then
            Hitbox.Expanded[part] = s
            if Config.HitboxSmooth then
                Hitbox.Settle[part] = tick() + 0.26
                TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Size = target}):Play()
            else
                part.Size = target
            end
        end

        st.applied = st.applied + 1
        Hitbox.Report[plr] = "covered"
    end)
end

--[[ PHYSICS-FRAME COLLISION ENFORCEMENT

    Roblox's Humanoid re-asserts CanCollide = true on HumanoidRootPart every
    physics step. A 0.1s poll loop loses that race, so an expanded part reads
    as a solid wall for most of the interval — that's the "running into people"
    problem.

    RunService.Stepped fires immediately BEFORE the physics solver runs, so
    clearing the flag here means the solver never sees a collidable part.
    Size and hit registration are untouched: CanQuery stays true, so raycasts
    (bullets) still land on the full expanded volume.

    The sweep is adaptive: if nothing re-flagged a part last pass, it drops to
    a 1-in-6 check so an idle hitbox costs effectively nothing.
]]
local phaseFrame, phaseDirty = 0, true

--[[ Proxy collision is cleared UNCONDITIONALLY and at full rate.

    A ragdoll implementation sets CanCollide = true on every BasePart in the
    character so the body lands on the floor. Our proxy is a BasePart in that
    model, so it gets flipped solid the moment somebody is knocked — and the
    0.1s sweep left up to a 100ms window where a 12-stud cube was a wall.
    That is the "sometimes I run into knocked people" bug.

    Clearing it here is free: the proxy is OUR part, anchored, in nobody's
    assembly. No mass recompute, no replication, nothing to throttle. So it is
    never gated behind PhaseThrough and never subject to the backoff.
]]
local function clearProxyCollision()
    for plr, p in pairs(Hitbox.Proxy) do
        if p.Parent then
            if p.CanCollide then p.CanCollide = false end
            if p.CanTouch   then p.CanTouch   = false end
        else
            Hitbox.Proxy[plr] = nil   -- removing an existing key mid-pairs is legal
        end
    end
end

local function enforcePhase()
    if not Config.HitboxEnabled then return end

    clearProxyCollision()

    if Config.HitboxMode ~= "Resize" then return end

    --[[ EVERY-FRAME SIZE + QUERY ENFORCEMENT — THE ACTUAL FIX.

        The old code only re-applied on the 0.1s sweep with an adaptive backoff.
        Zee Hood rewrites HumanoidRootPart.Size on its own every frame, so between
        sweeps the part sat at NORMAL size the vast majority of the time — the box
        "showed" but your bullet raycast hit a small target, so no damage landed.

        Re-asserting here on RunService.Stepped (EVERY frame, before the physics
        solver) keeps the part locked at full size and query-able at all times, so
        the shot always lands on the expanded volume. Writes are guarded to only
        fire when a value is actually wrong, so if the game ISN'T fighting us the
        cost is zero.
    ]]
    local s = Config.HitboxSize
    local target = Vector3.new(s, s, s)
    for part in pairs(Hitbox.Expanded) do
        if part and part.Parent then
            if (part.Size - target).Magnitude > 0.05 then part.Size = target end
            if not part.CanQuery then part.CanQuery = true end
            if Config.PhaseThrough and part.CanCollide then part.CanCollide = false end
            if Config.NoTouch and part.CanTouch then part.CanTouch = false end
        else
            Hitbox.Expanded[part] = nil
        end
    end
end

-- Stepped only. A second Heartbeat pass doubles the write rate for no gain.
bind(RunService.Stepped, enforcePhase)

local hitboxRunning = false
local function startHitbox()
    if hitboxRunning then return end
    hitboxRunning = true
    task.spawn(function()
        while Alive and Config.HitboxEnabled do
            local st = Hitbox.Stats
            st.applied, st.down, st.filtered, st.nopart, st.nochar, st.carried, st.total = 0, 0, 0, 0, 0, 0, 0
            Hitbox.Missing = false
            table.clear(Hitbox.Report)

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then pcall(applyHitbox, plr) end
            end

            -- Anyone uncovered? Come back in one frame instead of a full tick.
            -- Loading characters get picked up almost immediately, then the
            -- loop settles back to its normal rate once coverage is complete.
            if Hitbox.Missing then
                task.wait()
            else
                task.wait(math.max(Config.HitboxRefresh, 0.03))
            end
        end
        hitboxRunning = false
    end)
end

--============================================================================--
--  14. CHARACTER HOOKS  (instant restore the frame someone drops)
--============================================================================--

local function hookCharacter(plr, char)
    if plr == LocalPlayer then return end
    buildCache(plr)

    -- cover them on the spawn frame instead of waiting up to a full sweep tick
    -- (both modes now — Resize was previously left waiting a full tick)
    if Config.HitboxEnabled and Whitelist.IsTarget(plr) then
        pcall(applyHitbox, plr)
    end

    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 6)
    if not hum then return end

    local function drop()
        destroyProxy(plr)
        local p = char:FindFirstChild(Config.HitboxPart)
        if p then restorePart(p) end
    end

    -- bind(), not raw Connect — these must die with the script on unload
    bind(hum.Died, drop)

    local fx = char:FindFirstChild("BodyEffects") or char:WaitForChild("BodyEffects", 3)
    if fx then
        local ko = fx:FindFirstChild("K.O") or fx:FindFirstChild("KO")
        if ko and ko:IsA("BoolValue") then
            bind(ko.Changed, function(v) if v then drop() end end)
        end
    end
end

local function hookPlayer(plr)
    if plr == LocalPlayer then return end

    -- auto-whitelist: only in "Everyone" mode. In Selected/Blacklist your manual
    -- picks are the source of truth, so we must never auto-add players to the list
    -- (that was what made "Selected" silently fight the whole server).
    if Config.AutoWhitelist and Config.WhitelistMode == "Everyone" then
        Config.Whitelisted[plr.UserId] = true
        Config.Blacklisted[plr.UserId] = nil
    end

    if plr.Character then task.spawn(hookCharacter, plr, plr.Character) end

    bind(plr.CharacterAdded, function(c) task.spawn(hookCharacter, plr, c) end)
    bind(plr.CharacterRemoving, function(c)
        destroyProxy(plr)
        unghostCharacter(c)
        local p = c:FindFirstChild(Config.HitboxPart)
        if p then restorePart(p) end
        Cache[plr] = nil
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do pcall(hookPlayer, plr) end
bind(Players.PlayerAdded, hookPlayer)

--============================================================================--
--  14.5 TRIGGERBOT  (fires the game's own gun the frame an enemy is under the
--       cursor; zero-delay by default, with a reaction-delay dial and a
--       fire-rate dial. Uses the executor's click funcs so no remotes needed.)
--============================================================================--

-- forward-declared at chunk scope so the UI tab can reach them; everything
-- else stays inside the do-block to keep the main chunk's local count low.
local startTrigger
local TriggerStatus

do
    local LPMouse = LocalPlayer:GetMouse()
    local VIM; pcall(function() VIM = game:GetService("VirtualInputManager") end)

    local Trigger = {last = 0, pendingUntil = nil, pendingPlr = nil, keyDown = false}
    local triggerRunning = false

    --[[ FIRE A CLICK.

        We don't touch Da Hood's gun remotes at all — we just synthesise a real
        left-click so the game's OWN weapon script fires exactly as if you'd
        clicked. That means it works with every gun, respects the game's own
        fire cooldown, and there is nothing game-specific to break.

        Executors expose click funcs under different names; we try them in order
        of reliability and fall back to VirtualInputManager (hardware-level).
    ]]
    local function fireClick()
        if type(mouse1click) == "function" then
            pcall(mouse1click)
            return
        end
        if type(mouse1press) == "function" and type(mouse1release) == "function" then
            pcall(mouse1press)
            task.wait(0.015)
            pcall(mouse1release)
            return
        end
        if VIM then
            local loc = UserInputService:GetMouseLocation()
            pcall(function()
                VIM:SendMouseButtonEvent(loc.X, loc.Y, 0, true,  game, 0)
                VIM:SendMouseButtonEvent(loc.X, loc.Y, 0, false, game, 0)
            end)
        end
    end

    -- what the cursor is actually pointing at, resolved up to a real player.
    -- Mouse.Target respects CanQuery + line of sight, so if a wall is between
    -- you and the target the target simply isn't under the cursor -> no fire.
    local function targetUnderCursor()
        local t = LPMouse.Target
        if not t then return nil end
        local model = t:FindFirstAncestorWhichIsA("Model")
        while model do
            local plr = Players:GetPlayerFromCharacter(model)
            if plr and plr ~= LocalPlayer then return plr, model end
            model = model:FindFirstAncestorWhichIsA("Model")
        end
        return nil
    end

    local function gunEquipped()
        local char = LocalPlayer.Character
        return char and char:FindFirstChildOfClass("Tool") ~= nil
    end

    -- explicit line-of-sight test: ray from the camera to the target's root,
    -- ignoring our own character. First thing it hits must belong to them.
    local function inSight(char, part)
        local camera = cam()
        if not camera or not part then return true end
        local origin = camera.CFrame.Position
        local dir = part.Position - origin
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        params.FilterDescendantsInstances = LocalPlayer.Character and {LocalPlayer.Character} or {}
        local res = Workspace:Raycast(origin, dir, params)
        if not res then return true end
        return res.Instance:IsDescendantOf(char)
    end

    local function triggerStep()
        -- activation gate
        if Config.TriggerHoldMode and not Trigger.keyDown then
            Trigger.pendingUntil, Trigger.pendingPlr = nil, nil
            return
        end
        if Config.TriggerGunOnly and not gunEquipped() then
            Trigger.pendingUntil, Trigger.pendingPlr = nil, nil
            return
        end

        local plr, char = targetUnderCursor()
        if not plr or not char then
            Trigger.pendingUntil, Trigger.pendingPlr = nil, nil
            return
        end

        -- respect the Targets tab: in Selected mode only fire at whitelisted people,
        -- in Blacklist mode never fire at the ones you've excluded
        if Config.TriggerRespectWL and not Whitelist.IsTarget(plr) then
            Trigger.pendingUntil, Trigger.pendingPlr = nil, nil
            return
        end

        if Config.TriggerTeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
            return
        end
        if Config.TriggerDeadCheck and isDead(plr) then return end

        local tRoot = getRoot(char)
        local myChar = LocalPlayer.Character
        local myRoot = myChar and getRoot(myChar)
        if myRoot and tRoot and (tRoot.Position - myRoot.Position).Magnitude > Config.TriggerMaxDist then
            return
        end

        if Config.TriggerWallCheck and not inSight(char, tRoot) then
            Trigger.pendingUntil = nil
            return
        end

        local now = tick()

        -- reaction delay: only counted once per freshly-acquired target
        if Config.TriggerDelay and Config.TriggerDelay > 0 then
            if Trigger.pendingPlr ~= plr then
                Trigger.pendingPlr = plr
                Trigger.pendingUntil = now + Config.TriggerDelay / 1000
                return
            end
            if Trigger.pendingUntil and now < Trigger.pendingUntil then return end
        else
            Trigger.pendingPlr = plr
        end

        -- fire-rate cap between consecutive shots
        if now - Trigger.last < (Config.TriggerRate or 60) / 1000 then return end
        Trigger.last = now

        fireClick()
        if TriggerStatus then TriggerStatus.Text = "firing on " .. plr.DisplayName end
    end

    function startTrigger()
        if triggerRunning then return end
        triggerRunning = true
        task.spawn(function()
            while Alive and Config.TriggerEnabled do
                pcall(triggerStep)
                task.wait()   -- every frame -> effectively zero added latency
            end
            triggerRunning = false
        end)
    end

    -- hold-key state (separate from the menu keybind router; harmless if unused)
    bind(UserInputService.InputBegan, function(i, gpe)
        if gpe then return end
        if i.KeyCode == Config.TriggerKey then Trigger.keyDown = true end
    end)
    bind(UserInputService.InputEnded, function(i)
        if i.KeyCode == Config.TriggerKey then Trigger.keyDown = false end
    end)
end

--============================================================================--
--  15. ESP ENGINE
--============================================================================--

local Esp = {Objects = {}, Drawn = 0, Eligible = 0, Errors = 0, LastError = nil}
local EspStatus   -- UI label, assigned when the ESP tab builds

local function thumb(userId)
    return "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=150&h=150"
end

local function espColor(plr)
    if Config.EspRainbow then
        return Color3.fromHSV((tick() * 0.25 + (plr.UserId % 97) / 97) % 1, 0.75, 1)
    end
    if Config.EspTeamColor and plr.Team then
        local ok, c = pcall(function() return plr.TeamColor.Color end)
        if ok and c then return c end
    end
    if Config.WhitelistMode ~= "Everyone" and Config.Whitelisted[plr.UserId] then return C3(80, 255, 140) end
    return Theme.Accent
end

local function createEsp(plr)
    if Esp.Objects[plr] then return Esp.Objects[plr] end
    local o = {}

    local bb = new("BillboardGui", {
        Name = "mw_" .. plr.UserId, AlwaysOnTop = true, Size = UDim2.new(0, 160, 0, 90),
        StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0), LightInfluence = 0,
        Enabled = false, Parent = EspRoot,
    })

    local pfpHolder = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 48),
        Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = Theme.Panel, Parent = bb,
    })
    corner(pfpHolder, 23)
    local pfpStroke = new("UIStroke", {Thickness = 2, Color = Theme.Accent, Parent = pfpHolder})
    local pfp = new("ImageLabel", {
        Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2),
        BackgroundTransparency = 1, Image = thumb(plr.UserId), Parent = pfpHolder,
    })
    corner(pfp, 21)

    local nameLbl = new("TextLabel", {
        Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = C3(255,255,255), TextStrokeTransparency = 0.35, Text = plr.DisplayName, Parent = bb,
    })
    local infoLbl = new("TextLabel", {
        Position = UDim2.new(0, 0, 0, 63), Size = UDim2.new(1, 0, 0, 12),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10.5,
        TextColor3 = C3(200,200,210), TextStrokeTransparency = 0.5, Text = "", Parent = bb,
    })
    local hpBack = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 77),
        Size = UDim2.new(0, 62, 0, 4), BackgroundColor3 = C3(15,15,20), Parent = bb,
    })
    corner(hpBack, 2)
    local hpFill = new("Frame", {Size = UDim2.new(1,0,1,0), BackgroundColor3 = C3(80,255,120), BorderSizePixel = 0, Parent = hpBack})
    corner(hpFill, 2)

    local frame = new("Frame", {BackgroundTransparency = 1, Visible = false, Parent = EspRoot})
    local corners = {}
    for i = 1, 8 do corners[i] = new("Frame", {BorderSizePixel = 0, BackgroundColor3 = Theme.Accent, Visible = false, Parent = frame}) end

    local boxOutline = new("Frame", {Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Visible = false, Parent = frame})
    local boxStroke = new("UIStroke", {Thickness = 1.4, Color = Theme.Accent, Transparency = 0.15, Parent = boxOutline})

    local hpBar = new("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0, -5, 0, 0), Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = C3(0,0,0), BackgroundTransparency = 0.35, Parent = frame,
    })
    local hpBarFill = new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = C3(80,255,120), BorderSizePixel = 0, Parent = hpBar,
    })

    local cinName = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.new(0, 200, 0, 14),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C3(255,255,255),
        TextStrokeTransparency = 0.3, Text = plr.DisplayName, Parent = frame,
    })
    local cinInfo = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(0, 200, 0, 12),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10.5, TextColor3 = C3(210,210,220),
        TextStrokeTransparency = 0.4, Text = "", Parent = frame,
    })
    local cinTool = new("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 8, 0.5, 0), Size = UDim2.new(0, 120, 0, 12),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10.5, TextColor3 = C3(255,220,140),
        TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = frame,
    })

    local tracer = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
        Size = UDim2.new(0, 1, 0, 0), Visible = false, ZIndex = 0, Parent = EspRoot,
    })

    local arrow = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 26, 0, 26), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBlack, TextSize = 20, Text = "^", TextColor3 = Theme.Accent,
        Visible = false, Parent = EspRoot,
    })

    local highlight = new("Highlight", {
        FillColor = Theme.Accent, FillTransparency = 0.65, OutlineColor = C3(255,255,255),
        OutlineTransparency = 0.2, Enabled = false, Parent = EspRoot,
    })

    o.Billboard, o.PfpHolder, o.Pfp, o.PfpStroke = bb, pfpHolder, pfp, pfpStroke
    o.Name, o.Info, o.HpBack, o.HpFill = nameLbl, infoLbl, hpBack, hpFill
    o.Frame, o.Corners, o.BoxOutline, o.BoxStroke = frame, corners, boxOutline, boxStroke
    o.CinName, o.CinInfo, o.CinTool, o.HpBar, o.HpBarFill = cinName, cinInfo, cinTool, hpBar, hpBarFill
    o.Tracer, o.Arrow, o.Highlight = tracer, arrow, highlight

    Esp.Objects[plr] = o
    return o
end

local function destroyEsp(plr)
    local o = Esp.Objects[plr]
    if not o then return end
    Esp.Objects[plr] = nil
    for _, v in pairs(o) do
        if typeof(v) == "Instance" then pcall(function() v:Destroy() end) end
    end
end

local function hideEsp(o)
    if not o then return end
    o.Billboard.Enabled = false
    o.Frame.Visible = false
    o.Tracer.Visible = false
    o.Arrow.Visible = false
    o.Highlight.Enabled = false
end

local function setCorners(frame, corners, col, thickness)
    local w, h = frame.AbsoluteSize.X, frame.AbsoluteSize.Y
    local lx = math.clamp(w * 0.3, 4, 22)
    local ly = math.clamp(h * 0.18, 4, 22)
    local defs = {
        {UDim2.new(0, 0, 0, 0),            UDim2.new(0, lx, 0, thickness)},
        {UDim2.new(0, 0, 0, 0),            UDim2.new(0, thickness, 0, ly)},
        {UDim2.new(1, -lx, 0, 0),          UDim2.new(0, lx, 0, thickness)},
        {UDim2.new(1, -thickness, 0, 0),   UDim2.new(0, thickness, 0, ly)},
        {UDim2.new(0, 0, 1, -thickness),   UDim2.new(0, lx, 0, thickness)},
        {UDim2.new(0, 0, 1, -ly),          UDim2.new(0, thickness, 0, ly)},
        {UDim2.new(1, -lx, 1, -thickness), UDim2.new(0, lx, 0, thickness)},
        {UDim2.new(1, -thickness, 1, -ly), UDim2.new(0, thickness, 0, ly)},
    }
    for i, c in ipairs(corners) do
        c.Position = defs[i][1]
        c.Size = defs[i][2]
        c.BackgroundColor3 = col
        c.Visible = true
    end
end

--[[ Per-player draw, called through pcall from updateEsp.

    Previously the whole player loop lived inside ONE pcall. A single error on
    one player aborted the entire frame, so nobody later in the list got drawn
    — and since GetPlayers() order is stable, the same people went dark every
    frame. Isolating each player means one bad character can never blank
    anyone else.
]]
local function espPlayer(plr, camera, vp, center, myRoot)
            -- resolved live off the character; the cache is a hint, not a gate
            local char = plr.Character
            if not char or not char.Parent then
                if Esp.Objects[plr] then hideEsp(Esp.Objects[plr]) end
                return false
            end

            local e = getCache(plr) or {}
            local root = (e.Root and e.Root.Parent and e.Root) or getRoot(char)
            local head = (e.Head and e.Head.Parent and e.Head) or getHead(char) or root
            local hum  = (e.Hum and e.Hum.Parent and e.Hum) or char:FindFirstChildOfClass("Humanoid")

            local valid  = root and root.Parent and head and head.Parent
            local wanted = valid and Whitelist.IsTarget(plr)

            if not wanted then
                if Esp.Objects[plr] then hideEsp(Esp.Objects[plr]) end
                return false
            else
                local o = Esp.Objects[plr] or createEsp(plr)
                local dead = isDead(plr)
                local dist = myRoot and (myRoot.Position - root.Position).Magnitude or 0

                if dist > Config.EspMaxDistance or (dead and not Config.EspDeadFade) then
                    hideEsp(o)
                    return false   -- eligible but deliberately not drawn
                else
                    local col = dead and C3(120, 120, 130) or espColor(plr)
                    local fade = dead and 0.5 or 0
                    -- hum can legitimately be nil now that root/head no longer
                    -- gate the draw; a missing Humanoid must not cost the ESP
                    local hpNow = (hum and hum.Health) or 100
                    local maxHp = math.max((hum and hum.MaxHealth) or 100, 1)
                    local hp = math.clamp(hpNow / maxHp, 0, 1)
                    local hpCol = C3(255, 60, 60):Lerp(C3(80, 255, 120), hp)
                    local tool = char:FindFirstChildOfClass("Tool")
                    local toolName = tool and tool.Name or "Fists"

                    ------------------------------------------------ profile
                    local showProfile = (Config.EspStyle == "Profile" or Config.EspStyle == "Both")
                    o.Billboard.Enabled = showProfile
                    if showProfile then
                        o.Billboard.Adornee = head
                        o.Pfp.ImageTransparency = fade
                        o.PfpStroke.Color = col
                        o.PfpStroke.Transparency = fade
                        o.Name.Text = Config.EspName and plr.DisplayName or ""
                        o.Name.TextTransparency = fade
                        o.Info.TextTransparency = fade

                        local bits = {}
                        if Config.EspDistance then table.insert(bits, math.floor(dist) .. "m") end
                        if Config.EspHealth   then table.insert(bits, math.floor(hpNow) .. "hp") end
                        if Config.EspTool     then table.insert(bits, toolName) end
                        if dead               then table.insert(bits, "DOWN") end
                        o.Info.Text = table.concat(bits, "  |  ")

                        o.HpBack.Visible = Config.EspHealth
                        o.HpFill.Size = UDim2.new(hp, 0, 1, 0)
                        o.HpFill.BackgroundColor3 = hpCol

                        local scale = math.clamp(1 - dist / (Config.EspMaxDistance * 1.4), 0.45, 1)
                        local s = Config.EspAvatarSize * scale
                        o.PfpHolder.Size = UDim2.new(0, s, 0, s)
                    end

                    ------------------------------------------------ cinematic
                    if Config.EspStyle == "Cinematic" or Config.EspStyle == "Both" then
                        local top, onA = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3.1, 0))
                        local bot, onB = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.4, 0))

                        if (onA or onB) and top.Z > 0 then
                            local h = math.abs(top.Y - bot.Y)
                            local w = h * 0.62
                            o.Frame.Visible = true
                            o.Frame.Position = UDim2.new(0, top.X - w / 2, 0, math.min(top.Y, bot.Y))
                            o.Frame.Size = UDim2.new(0, w, 0, h)

                            if Config.EspBox then
                                if Config.EspBoxStyle == "Corner" then
                                    o.BoxOutline.Visible = false
                                    setCorners(o.Frame, o.Corners, col, 2)
                                else
                                    for _, c in ipairs(o.Corners) do c.Visible = false end
                                    o.BoxOutline.Visible = true
                                    o.BoxStroke.Color = col
                                    o.BoxStroke.Thickness   = (Config.EspBoxStyle == "Glow") and 3 or 1.4
                                    o.BoxStroke.Transparency = (Config.EspBoxStyle == "Glow") and 0.45 or 0.1
                                end
                            else
                                o.BoxOutline.Visible = false
                                for _, c in ipairs(o.Corners) do c.Visible = false end
                            end

                            o.CinName.Visible = Config.EspName
                            o.CinName.TextColor3 = dead and C3(150,150,160) or C3(255,255,255)

                            local bits = {}
                            if Config.EspDistance then table.insert(bits, math.floor(dist) .. "m") end
                            if dead then table.insert(bits, "DOWN") end
                            o.CinInfo.Text = table.concat(bits, "  |  ")
                            o.CinInfo.Visible = #bits > 0

                            o.CinTool.Visible = Config.EspTool
                            o.CinTool.Text = toolName

                            o.HpBar.Visible = Config.EspHealth
                            o.HpBarFill.Size = UDim2.new(1, 0, hp, 0)
                            o.HpBarFill.BackgroundColor3 = hpCol

                            if Config.EspTracer then
                                local origin
                                if Config.EspTracerFrom == "Bottom" then origin = Vector2.new(vp.X / 2, vp.Y)
                                elseif Config.EspTracerFrom == "Center" then origin = center
                                else origin = UserInputService:GetMouseLocation() end
                                local delta = Vector2.new(top.X, bot.Y) - origin
                                o.Tracer.Visible = true
                                o.Tracer.BackgroundColor3 = col
                                o.Tracer.Position = UDim2.new(0, origin.X, 0, origin.Y)
                                o.Tracer.Size = UDim2.new(0, 1.4, 0, delta.Magnitude)
                                o.Tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X)) - 90
                            else
                                o.Tracer.Visible = false
                            end
                            o.Arrow.Visible = false
                        else
                            o.Frame.Visible = false
                            o.Tracer.Visible = false
                            if Config.EspArrows then
                                local rel = camera.CFrame:PointToObjectSpace(root.Position)
                                local ang = math.atan2(rel.X, -rel.Z)
                                local radius = math.min(vp.X, vp.Y) * 0.32
                                o.Arrow.Visible = true
                                o.Arrow.TextColor3 = col
                                o.Arrow.Rotation = math.deg(ang)
                                o.Arrow.Position = UDim2.new(0, center.X + math.sin(ang) * radius,
                                                             0, center.Y - math.cos(ang) * radius)
                            else
                                o.Arrow.Visible = false
                            end
                        end
                    else
                        o.Frame.Visible = false
                        o.Tracer.Visible = false
                        o.Arrow.Visible = false
                    end

                    ------------------------------------------------ chams
                    if Config.EspChams then
                        o.Highlight.Enabled = true
                        -- guarded: writing Adornee every frame fires Changed needlessly
                        if o.Highlight.Adornee ~= char then o.Highlight.Adornee = char end
                        o.Highlight.FillColor = col
                        o.Highlight.FillTransparency = dead and 0.85 or 0.62
                    else
                        o.Highlight.Enabled = false
                    end
                end
                return true
            end
end

local function updateEsp()
    if not Config.EspEnabled then
        for _, o in pairs(Esp.Objects) do hideEsp(o) end
        Esp.Drawn, Esp.Eligible, Esp.Errors = 0, 0, 0
        return
    end

    local camera = cam()
    if not camera then return end

    local myRoot = LocalPlayer.Character and getRoot(LocalPlayer.Character)
    local vp = camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)

    local drawn, eligible, errors = 0, 0, 0

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if Whitelist.IsTarget(plr) then eligible = eligible + 1 end

            -- isolated: one player's failure cannot blank the rest of the list
            local ok, res = pcall(espPlayer, plr, camera, vp, center, myRoot)
            if ok then
                if res then drawn = drawn + 1 end
            else
                errors = errors + 1
                Esp.LastError = tostring(res)
            end
        end
    end

    Esp.Drawn, Esp.Eligible, Esp.Errors = drawn, eligible, errors
end

--============================================================================--
--  15b. CANONICAL LEAVE CLEANUP
--
--  Lives at top level, NOT inside a safeBuild block. If the Targets tab ever
--  fails to build, its own PlayerRemoving handler never binds and every
--  leaver would leak ~15 ESP instances plus a proxy part. This one always runs.
--============================================================================--

bind(Players.PlayerRemoving, function(plr)
    destroyProxy(plr)
    destroyEsp(plr)
    Cache[plr] = nil
    Hitbox.Report[plr] = nil
    Config.Whitelisted[plr.UserId] = nil
    Config.Blacklisted[plr.UserId] = nil
end)

--============================================================================--
--  16. 4D PREVIEW
--============================================================================--

local Preview = {Angle = 0, Spin = true}

local function projectToViewport(camera, worldPos, size)
    local rel = camera.CFrame:PointToObjectSpace(worldPos)
    if rel.Z > -0.05 then return nil end
    local aspect = size.X / math.max(size.Y, 1)
    local tanHalf = math.tan(math.rad(camera.FieldOfView / 2))
    local x = (rel.X / (-rel.Z * tanHalf * aspect)) * 0.5 + 0.5
    local y = (-rel.Y / (-rel.Z * tanHalf)) * 0.5 + 0.5
    return Vector2.new(x * size.X, y * size.Y)
end

local function buildPreview(parent)
    local holder = new("Frame", {Size = UDim2.new(1, 0, 0, 270), BackgroundColor3 = Theme.Card, Parent = parent})
    corner(holder, 10); stroke(holder, "Stroke", 1); themed(holder, "BackgroundColor3", "Card")

    local vpf = new("ViewportFrame", {
        Size = UDim2.new(1, -16, 1, -16), Position = UDim2.new(0, 8, 0, 8),
        BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.2,
        Ambient = C3(150, 150, 170), LightColor = C3(255, 255, 255),
        LightDirection = Vector3.new(-0.4, -1, -0.3), Parent = holder,
    })
    corner(vpf, 8); themed(vpf, "BackgroundColor3", "Bg")

    local grad = new("Frame", {Size = UDim2.new(1,0,1,0), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.9, ZIndex = 0, Parent = vpf})
    corner(grad, 8)
    local gg = new("UIGradient", {Color = ColorSequence.new(Theme.Accent, Theme.Accent2), Parent = grad})

    local world = new("WorldModel", {Parent = vpf})
    local pcam = new("Camera", {FieldOfView = 40, Parent = vpf})
    vpf.CurrentCamera = pcam

    local overlay = new("Frame", {Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, ZIndex = 5, Parent = vpf})

    local ovFrame = new("Frame", {BackgroundTransparency = 1, ZIndex = 6, Visible = false, Parent = overlay})
    local ovCorners = {}
    for i = 1, 8 do ovCorners[i] = new("Frame", {BorderSizePixel = 0, BackgroundColor3 = Theme.Accent, ZIndex = 6, Visible = false, Parent = ovFrame}) end
    local ovStrokeHost = new("Frame", {Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, ZIndex = 6, Visible = false, Parent = ovFrame})
    local ovStroke = new("UIStroke", {Thickness = 1.4, Color = Theme.Accent, Parent = ovStrokeHost})

    local ovName = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.new(0, 180, 0, 14),
        BackgroundTransparency = 1, ZIndex = 7, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = C3(255,255,255), TextStrokeTransparency = 0.3, Text = "", Parent = ovFrame,
    })
    local ovInfo = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(0, 180, 0, 12),
        BackgroundTransparency = 1, ZIndex = 7, Font = Enum.Font.Gotham, TextSize = 10.5,
        TextColor3 = C3(210,210,220), TextStrokeTransparency = 0.4, Text = "", Parent = ovFrame,
    })
    local ovHp = new("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0, -5, 0, 0), Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = C3(0,0,0), BackgroundTransparency = 0.35, ZIndex = 6, Parent = ovFrame,
    })
    new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0.82, 0),
        BackgroundColor3 = C3(80,255,120), BorderSizePixel = 0, ZIndex = 6, Parent = ovHp,
    })

    local ovPfpHolder = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(0, 44, 0, 44), BackgroundColor3 = Theme.Panel,
        ZIndex = 7, Visible = false, Parent = overlay,
    })
    corner(ovPfpHolder, 22)
    local ovPfpStroke = new("UIStroke", {Thickness = 2, Color = Theme.Accent, Parent = ovPfpHolder})
    local ovPfp = new("ImageLabel", {
        Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundTransparency = 1,
        ZIndex = 7, Image = thumb(LocalPlayer.UserId), Parent = ovPfpHolder,
    })
    corner(ovPfp, 20)

    local caption = new("TextLabel", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8), Size = UDim2.new(1, -20, 0, 14),
        BackgroundTransparency = 1, ZIndex = 8, Font = Enum.Font.Gotham, TextSize = 11,
        Text = "live preview  |  drag to spin", TextXAlignment = Enum.TextXAlignment.Left, Parent = vpf,
    })
    themed(caption, "TextColor3", "Sub")

    Preview.Holder, Preview.Vp, Preview.Cam, Preview.World = holder, vpf, pcam, world
    Preview.Overlay = {
        Frame = ovFrame, Corners = ovCorners, StrokeHost = ovStrokeHost, Stroke = ovStroke,
        Name = ovName, Info = ovInfo, Hp = ovHp, PfpHolder = ovPfpHolder, Pfp = ovPfp,
        PfpStroke = ovPfpStroke, Grad = gg,
    }

    local lastX
    local function spin(i)
        if not lastX then return end
        Preview.Angle = Preview.Angle + (i.Position.X - lastX) * 0.008
        lastX = i.Position.X
    end
    vpf.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            lastX = i.Position.X
            Preview.Spin = false
            DragTargets[spin] = true
        end
    end)
    table.insert(ReleaseCallbacks, function()
        if lastX then
            lastX = nil
            task.delay(1.2, function() Preview.Spin = true end)
        end
    end)

    return holder
end

local function loadPreviewModel(plr)
    plr = plr or LocalPlayer
    if not Preview.World or not Preview.World.Parent then return false end

    local char = plr.Character
    if not char then return false end

    if Preview.Model then pcall(function() Preview.Model:Destroy() end) Preview.Model = nil end

    local restore = {}
    local ok, clone = pcall(function()
        for _, d in ipairs(char:GetDescendants()) do
            if not d.Archivable then table.insert(restore, d); d.Archivable = true end
        end
        local wasArchivable = char.Archivable
        char.Archivable = true
        local c = char:Clone()
        char.Archivable = wasArchivable
        return c
    end)
    for _, d in ipairs(restore) do pcall(function() d.Archivable = false end) end

    if not ok or not clone then return false end

    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BaseScript") or d:IsA("BillboardGui") or d:IsA("SurfaceGui")
        or d:IsA("Highlight") or d:IsA("Sound") or d:IsA("ParticleEmitter") then
            pcall(function() d:Destroy() end)
        elseif d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
        end
    end

    clone.Parent = Preview.World
    Preview.Model = clone
    Preview.Target = plr
    Preview.Overlay.Pfp.Image = thumb(plr.UserId)
    Preview.Overlay.Name.Text = plr.DisplayName
    return true
end

local function updatePreview(dt)
    local P = Preview
    if not P.Vp or not P.Vp.Parent then return end
    if not P.Holder or not P.Holder.Visible then return end
    if not P.Holder:IsDescendantOf(ScreenGui) then return end
    -- skip entirely when its tab isn't the active one
    if not CurrentTab or CurrentTab.Name ~= "4D Display" then return end

    -- LAZY CLONE: the character is only cloned into the viewport the first time
    -- you actually open this tab (and re-cloned if it goes stale), never on
    -- inject. No ViewportFrame render cost until you ask for it.
    if not P.Model or not P.Model.Parent then
        if not P.Loading then
            P.Loading = true
            task.spawn(function() pcall(loadPreviewModel, LocalPlayer); P.Loading = false end)
        end
        return
    end

    local root = P.Model:FindFirstChild("HumanoidRootPart") or P.Model:FindFirstChild("Torso")
    local head = P.Model:FindFirstChild("Head")
    if not root then return end

    if P.Spin then P.Angle = P.Angle + dt * 0.55 end

    local pivot = root.Position + Vector3.new(0, 0.3, 0)
    local t = tick()
    local bob  = math.sin(t * 0.9) * 0.9
    local tilt = math.sin(t * 0.45) * 0.12
    local camPos = Vector3.new(pivot.X + math.sin(P.Angle) * 9.2, pivot.Y + 1.4 + bob, pivot.Z + math.cos(P.Angle) * 9.2)
    P.Cam.CFrame = CFrame.lookAt(camPos, pivot) * CFrame.Angles(0, 0, tilt)

    local ov = P.Overlay
    ov.Grad.Rotation = (P.Angle * 40) % 360

    local size = P.Vp.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then return end

    local top = projectToViewport(P.Cam, root.Position + Vector3.new(0, 3.1, 0), size)
    local bot = projectToViewport(P.Cam, root.Position - Vector3.new(0, 3.4, 0), size)

    if top and bot then
        local h = math.abs(top.Y - bot.Y)
        local w = h * 0.62
        ov.Frame.Visible = true
        ov.Frame.Position = UDim2.new(0, top.X - w / 2, 0, math.min(top.Y, bot.Y))
        ov.Frame.Size = UDim2.new(0, w, 0, h)

        local col = Config.EspRainbow and Color3.fromHSV((t * 0.25) % 1, 0.75, 1) or Theme.Accent

        if Config.EspBox then
            if Config.EspBoxStyle == "Corner" then
                ov.StrokeHost.Visible = false
                setCorners(ov.Frame, ov.Corners, col, 2)
            else
                for _, c in ipairs(ov.Corners) do c.Visible = false end
                ov.StrokeHost.Visible = true
                ov.Stroke.Color = col
                ov.Stroke.Thickness    = (Config.EspBoxStyle == "Glow") and 3 or 1.4
                ov.Stroke.Transparency = (Config.EspBoxStyle == "Glow") and 0.45 or 0.1
            end
        else
            ov.StrokeHost.Visible = false
            for _, c in ipairs(ov.Corners) do c.Visible = false end
        end

        ov.Name.Visible = Config.EspName
        ov.Info.Visible = Config.EspDistance or Config.EspTool

        -- real numbers off the previewed player, not a hardcoded placeholder
        local bits = {}
        local tp = P.Target
        if tp and tp.Parent then
            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local tRoot  = tp.Character and tp.Character:FindFirstChild("HumanoidRootPart")
            if Config.EspDistance and myRoot and tRoot then
                table.insert(bits, math.floor((myRoot.Position - tRoot.Position).Magnitude) .. "m")
            end
            if Config.EspTool then
                local tl = tp.Character and tp.Character:FindFirstChildOfClass("Tool")
                table.insert(bits, tl and tl.Name or "Fists")
            end
        end
        ov.Info.Text = #bits > 0 and table.concat(bits, "  |  ") or "preview"
        ov.Hp.Visible = Config.EspHealth

        if (Config.EspStyle == "Profile" or Config.EspStyle == "Both") and head then
            local hp = projectToViewport(P.Cam, head.Position + Vector3.new(0, 2.4, 0), size)
            if hp then
                local s = Config.EspAvatarSize * 0.9
                ov.PfpHolder.Visible = true
                ov.PfpHolder.Position = UDim2.new(0, hp.X, 0, hp.Y)
                ov.PfpHolder.Size = UDim2.new(0, s, 0, s)
                ov.PfpStroke.Color = col
            end
        else
            ov.PfpHolder.Visible = false
        end
    else
        ov.Frame.Visible = false
        ov.PfpHolder.Visible = false
    end
end

--============================================================================--
--  17. PLAYER LIST
--============================================================================--

local PlayerRows = {}
local RefreshList

local function buildPlayerList(parent)
    local holder = new("Frame", {Size = UDim2.new(1, 0, 0, 300), BackgroundColor3 = Theme.Card, Parent = parent})
    corner(holder, 10); stroke(holder, "Stroke", 1); themed(holder, "BackgroundColor3", "Card")

    local search = new("TextBox", {
        Position = UDim2.new(0, 10, 0, 10), Size = UDim2.new(1, -20, 0, 28),
        BackgroundColor3 = Theme.Panel, Font = Enum.Font.Gotham, TextSize = 12,
        PlaceholderText = "search player...", Text = "", ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = holder,
    })
    corner(search, 7); stroke(search, "Stroke", 1); pad(search, 9, 9, 0, 0)
    themed(search, "BackgroundColor3", "Panel"); themed(search, "TextColor3", "Text")
    themed(search, "PlaceholderColor3", "Sub")

    local list = new("ScrollingFrame", {
        Position = UDim2.new(0, 10, 0, 46), Size = UDim2.new(1, -20, 1, -56),
        BackgroundTransparency = 1, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = holder,
    })
    themed(list, "ScrollBarImageColor3", "Accent")
    new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})

    function RefreshList()
        for _, r in pairs(PlayerRows) do pcall(function() r:Destroy() end) end
        table.clear(PlayerRows)

        -- Every row registers themed() entries. Rebuilding the list repeatedly
        -- would grow ThemedObjects forever with dead references, so prune here.
        for i = #ThemedObjects, 1, -1 do
            local te = ThemedObjects[i]
            if not te.inst or not te.inst.Parent then table.remove(ThemedObjects, i) end
        end

        local q = string.lower(search.Text)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local hay = string.lower(plr.Name .. " " .. plr.DisplayName)
                if q == "" or string.find(hay, q, 1, true) then
                    local row = new("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.Panel, Parent = list})
                    corner(row, 8); themed(row, "BackgroundColor3", "Panel")

                    local av = new("ImageLabel", {
                        Position = UDim2.new(0, 7, 0.5, -15), Size = UDim2.new(0, 30, 0, 30),
                        BackgroundColor3 = Theme.Bg, Image = thumb(plr.UserId), Parent = row,
                    })
                    corner(av, 15)

                    local nm = new("TextLabel", {
                        Position = UDim2.new(0, 46, 0, 7), Size = UDim2.new(1, -170, 0, 14),
                        BackgroundTransparency = 1, Font = Enum.Font.GothamSemibold, TextSize = 12,
                        Text = plr.DisplayName, TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
                    })
                    themed(nm, "TextColor3", "Text")

                    local un = new("TextLabel", {
                        Position = UDim2.new(0, 46, 0, 23), Size = UDim2.new(1, -170, 0, 13),
                        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10.5,
                        Text = "@" .. plr.Name, TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
                    })
                    themed(un, "TextColor3", "Sub")

                    local eye = new("TextButton", {
                        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0),
                        Size = UDim2.new(0, 30, 0, 26), BackgroundColor3 = Theme.Card, AutoButtonColor = false,
                        Font = Enum.Font.GothamBold, TextSize = 11, Text = "3D", Parent = row,
                    })
                    corner(eye, 7); themed(eye, "BackgroundColor3", "Card"); themed(eye, "TextColor3", "Sub")
                    eye.MouseButton1Click:Connect(function()
                        if loadPreviewModel(plr) then
                            Notify("Preview", plr.DisplayName .. " loaded into the 4D display.", 2.5)
                        else
                            Notify("Preview", "Couldn't clone that character right now.", 2.5, "warn")
                        end
                    end)

                    local pick = new("TextButton", {
                        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
                        Size = UDim2.new(0, 82, 0, 26), BackgroundColor3 = Theme.Card, AutoButtonColor = false,
                        Font = Enum.Font.GothamSemibold, TextSize = 11.5, Text = "", Parent = row,
                    })
                    corner(pick, 7)

                    local function paint()
                        local tbl = (Config.WhitelistMode == "Blacklist") and Config.Blacklisted or Config.Whitelisted
                        local on = tbl[plr.UserId] == true
                        if Config.WhitelistMode == "Blacklist" then
                            pick.Text = on and "IGNORED" or "ignore"
                            pick.TextColor3 = on and C3(255, 90, 110) or Theme.Sub
                            pick.BackgroundColor3 = on and C3(48, 20, 26) or Theme.Card
                        else
                            pick.Text = on and "TARGET" or "add"
                            pick.TextColor3 = on and C3(80, 255, 140) or Theme.Sub
                            pick.BackgroundColor3 = on and C3(20, 44, 30) or Theme.Card
                        end
                    end
                    paint()

                    pick.MouseButton1Click:Connect(function()
                        local added = Whitelist.Toggle(plr)
                        paint()
                        Notify(added and "Added" or "Removed",
                               plr.DisplayName .. (added and " is now a target." or " is no longer a target."), 2.2)
                    end)

                    PlayerRows[plr] = row
                end
            end
        end
    end

    search:GetPropertyChangedSignal("Text"):Connect(function() pcall(RefreshList) end)
    bind(Players.PlayerAdded, function() task.wait(0.4) pcall(RefreshList) end)
    bind(Players.PlayerRemoving, function(plr)
        Config.Whitelisted[plr.UserId] = nil
        Config.Blacklisted[plr.UserId] = nil
        Cache[plr] = nil
        destroyEsp(plr)
        task.wait(0.2)
        pcall(RefreshList)
    end)

    RefreshList()
    return holder
end

--============================================================================--
--  18. THEME SWAP
--============================================================================--

local ThemeSwatches = {}

local function applyTheme(name)
    local t = Themes[name]
    if not t then return end
    Theme = t
    Config.Theme = name

    for i = #ThemedObjects, 1, -1 do
        local e = ThemedObjects[i]
        if not e.inst or not e.inst.Parent then
            table.remove(ThemedObjects, i)
        else
            tween(e.inst, 0.25, {[e.prop] = Theme[e.key]})
        end
    end

    for _, sw in ipairs(ThemeSwatches) do pcall(sw.Update) end

    -- gradients, orbs and rotating rims paint their own colours; poke them here
    for _, fn in ipairs(ChromeThemeRefresh) do pcall(fn) end

    for _, o in pairs(Esp.Objects) do
        pcall(function()
            o.PfpStroke.Color = Theme.Accent
            o.BoxStroke.Color = Theme.Accent
        end)
    end
    if Preview.Overlay then
        pcall(function()
            Preview.Overlay.Grad.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
            Preview.Overlay.Stroke.Color = Theme.Accent
            Preview.Overlay.PfpStroke.Color = Theme.Accent
        end)
    end
end

local function buildThemeGrid(parent)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Parent = parent,
    })
    new("UIGridLayout", {
        CellSize = UDim2.new(0, 158, 0, 58), CellPadding = UDim2.new(0, 8, 0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder,
    })

    local names = {}
    for n in pairs(Themes) do table.insert(names, n) end
    table.sort(names)

    for _, name in ipairs(names) do
        local t = Themes[name]
        local card = new("TextButton", {BackgroundColor3 = t.Panel, AutoButtonColor = false, Text = "", Parent = holder})
        corner(card, 9)
        local cs = new("UIStroke", {Thickness = 1, Color = t.Stroke, Parent = card})

        for i, col in ipairs({t.Accent, t.Accent2, t.Card}) do
            local d = new("Frame", {
                Position = UDim2.new(0, 10 + (i - 1) * 16, 0, 10), Size = UDim2.new(0, 14, 0, 14),
                BackgroundColor3 = col, Parent = card,
            })
            corner(d, 7)
        end

        new("TextLabel", {
            Position = UDim2.new(0, 10, 0, 30), Size = UDim2.new(1, -20, 0, 18),
            BackgroundTransparency = 1, Font = Enum.Font.GothamSemibold, TextSize = 11.5, Text = name,
            TextColor3 = t.Text, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
        })

        local check = new("TextLabel", {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.new(0, 18, 0, 18),
            BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13, Text = "ON",
            TextColor3 = t.Accent, Visible = false, Parent = card,
        })

        local sw = {}
        function sw.Update()
            local active = (Config.Theme == name)
            check.Visible = active
            cs.Color = active and t.Accent or t.Stroke
            cs.Thickness = active and 1.8 or 1
        end
        sw.Update()
        table.insert(ThemeSwatches, sw)

        card.MouseEnter:Connect(function() tween(card, 0.14, {BackgroundColor3 = t.Card}) end)
        card.MouseLeave:Connect(function() tween(card, 0.14, {BackgroundColor3 = t.Panel}) end)
        card.MouseButton1Click:Connect(function()
            applyTheme(name)
            Notify("Theme", name .. " applied.", 2)
        end)
    end
    return holder
end

--============================================================================--
--  18.5 CONFIG / PRESET ENGINE
--
--  Serializes the whole Config table (enums + colors handled explicitly) to
--  JSON, saves named presets under MoneyWare/configs, and loads them back LIVE:
--  every engine is re-applied and the settings tabs are rebuilt so widgets show
--  the loaded values. Falls back to clipboard export/import where a host lacks
--  file IO. Session-specific player picks are deliberately never persisted.
--============================================================================--

local HttpService = game:GetService("HttpService")

local FOLDER     = "MoneyWare"
local CFG_FOLDER = "MoneyWare/configs"
local AUTOLOAD   = "MoneyWare/autoload.txt"

local hasFS  = (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function")
local canDel = (typeof(delfile)  == "function")
local canList= (typeof(listfiles)== "function")

local function ensureFolders()
    if not hasFS or typeof(makefolder) ~= "function" then return end
    pcall(function() if typeof(isfolder) ~= "function" or not isfolder(FOLDER)     then makefolder(FOLDER)     end end)
    pcall(function() if typeof(isfolder) ~= "function" or not isfolder(CFG_FOLDER) then makefolder(CFG_FOLDER) end end)
end
ensureFolders()

-- never persist live/session state
local SAVE_SKIP = {Whitelisted = true, Blacklisted = true, ActivePreset = true}

local function encodeValue(v)
    local tv = typeof(v)
    if tv == "EnumItem" then
        return {__t = "enum", enum = tostring(v.EnumType):gsub("^Enum%.", ""), name = v.Name}
    elseif tv == "Color3" then
        return {__t = "color", r = math.floor(v.R * 255 + 0.5), g = math.floor(v.G * 255 + 0.5), b = math.floor(v.B * 255 + 0.5)}
    end
    return v
end

local function decodeValue(v)
    if type(v) == "table" and v.__t then
        if v.__t == "enum" then
            local ok, item = pcall(function()
                for _, e in ipairs(Enum[v.enum]:GetEnumItems()) do
                    if e.Name == v.name then return e end
                end
            end)
            return ok and item or nil
        elseif v.__t == "color" then
            return Color3.fromRGB(v.r or 0, v.g or 0, v.b or 0)
        end
    end
    return v
end

local function serialize()
    local out = {}
    for k, v in pairs(Config) do
        if not SAVE_SKIP[k] then
            local tv = typeof(v)
            if tv == "number" or tv == "boolean" or tv == "string" or tv == "EnumItem" or tv == "Color3" then
                out[k] = encodeValue(v)
            end
        end
    end
    return out
end

local function applyDecoded(data)
    for k, v in pairs(data) do
        if not SAVE_SKIP[k] then
            local dv = decodeValue(v)
            if dv ~= nil then Config[k] = dv end
        end
    end
end

-- assigned in the tabs section; regenerates the settings widgets from Config
local rebuildSettingsTabs

-- push a freshly-loaded Config back into every live system
local function reapplyLiveState()
    if Config.Theme and Themes[Config.Theme] then applyTheme(Config.Theme) end
    pcall(function() UIScaler.Scale = Config.UIScale end)
    pcall(function() Watermark.Visible = Config.Watermark end)

    if Config.HitboxEnabled then startHitbox()
    else task.spawn(function() task.wait(0.1); restoreAll() end) end

    if Config.TriggerEnabled then startTrigger() end
    if not Config.EspEnabled then for _, o in pairs(Esp.Objects) do hideEsp(o) end end

    if RefreshList then pcall(RefreshList) end
    if rebuildSettingsTabs then pcall(rebuildSettingsTabs) end
end

local function sanitizeName(name)
    name = tostring(name or ""):gsub("[^%w%-_ ]", ""):gsub("%s+", "_")
    if name == "" then name = "preset" end
    return name
end

local ConfigIO = {}
function ConfigIO.HasFS() return hasFS end

-- stock settings captured now, before any preset can mutate Config
local DEFAULTS_JSON = (function()
    local ok, j = pcall(function() return HttpService:JSONEncode(serialize()) end)
    return ok and j or nil
end)()

function ConfigIO.Save(name)
    name = sanitizeName(name)
    local ok, json = pcall(function() return HttpService:JSONEncode(serialize()) end)
    if not ok then return false, "encode failed" end
    if hasFS then
        ensureFolders()
        local wok = pcall(function() writefile(CFG_FOLDER .. "/" .. name .. ".json", json) end)
        if not wok then return false, "write failed" end
    end
    Config.ActivePreset = name
    return true, name
end

function ConfigIO.Load(name)
    if not hasFS then return false, "no file system" end
    local path = CFG_FOLDER .. "/" .. name .. ".json"
    if not isfile(path) then return false, "not found" end
    local rok, json = pcall(function() return readfile(path) end)
    if not rok then return false, "read failed" end
    local dok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not dok or type(data) ~= "table" then return false, "corrupt" end
    applyDecoded(data)
    Config.ActivePreset = name
    reapplyLiveState()
    return true, name
end

function ConfigIO.Delete(name)
    if not hasFS or not canDel then return false end
    local path = CFG_FOLDER .. "/" .. name .. ".json"
    if isfile(path) then pcall(function() delfile(path) end); return true end
    return false
end

function ConfigIO.List()
    local names = {}
    if hasFS and canList then
        local ok, files = pcall(function() return listfiles(CFG_FOLDER) end)
        if ok and files then
            for _, f in ipairs(files) do
                local n = tostring(f):match("([^/\\]+)%.json$")
                if n then table.insert(names, n) end
            end
        end
    end
    table.sort(names)
    return names
end

function ConfigIO.Export()
    local ok, json = pcall(function() return HttpService:JSONEncode(serialize()) end)
    if not ok then return false end
    if typeof(setclipboard) == "function" then pcall(function() setclipboard(json) end) end
    return true, json
end

function ConfigIO.Import(json)
    if type(json) ~= "string" or json == "" then return false, "empty" end
    local dok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not dok or type(data) ~= "table" then return false, "invalid json" end
    applyDecoded(data)
    reapplyLiveState()
    return true
end

function ConfigIO.Reset()
    if not DEFAULTS_JSON then return false end
    Config.ActivePreset = "default"
    return ConfigIO.Import(DEFAULTS_JSON)
end

function ConfigIO.SetAutoload(name)
    if not hasFS then return end
    if name and name ~= "" then
        pcall(function() writefile(AUTOLOAD, name) end)
    elseif canDel then
        pcall(function() if isfile(AUTOLOAD) then delfile(AUTOLOAD) end end)
    end
end

function ConfigIO.GetAutoload()
    if not hasFS or not isfile(AUTOLOAD) then return nil end
    local ok, n = pcall(function() return readfile(AUTOLOAD) end)
    if ok and n and n ~= "" then return (n:gsub("%s+$", "")) end
    return nil
end

--============================================================================--
--  19. TABS + CONTENT  (each block fault-isolated)
--============================================================================--

local function safeBuild(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[MoneyWare] section '" .. label .. "' failed to build: " .. tostring(err))
        task.delay(1, function() Notify("Build warning", label .. " tab had an issue — everything else still works.", 5, "warn") end)
    end
end

UI.TabCategory("Combat")
local TabHit    = UI.Tab("Hitbox",     "H")
local TabTrigger= UI.Tab("Triggerbot", "F")
local TabTarget = UI.Tab("Targets",    "T")
UI.TabCategory("Visuals")
local TabEsp    = UI.Tab("ESP",        "E")
local TabPrev   = UI.Tab("4D Display", "D")
local TabTheme  = UI.Tab("Themes",     "P")
UI.TabCategory("System")
local TabCfg    = UI.Tab("Config",     "C")
local TabSet    = UI.Tab("Settings",   "S")

local function buildHitbox()
    local s = UI.Section(TabHit, "Hitbox Expander", "grows the target part so shots register wide")

    UI.Toggle(s, "Enable Hitbox Expander", Config.HitboxEnabled, function(v)
        Config.HitboxEnabled = v
        if v then
            startHitbox()
            Notify("Hitbox", "Online — " .. Config.HitboxPart .. " at " .. Config.HitboxSize .. " studs.", 3)
        else
            task.spawn(function()
                task.wait(math.max(Config.HitboxRefresh, 0.03) + 0.05)
                restoreAll()
            end)
            Notify("Hitbox", "Off. All parts restored.", 3)
        end
    end)

    UI.Dropdown(s, "Mode", {"Proxy", "Resize"}, Config.HitboxMode, function(v)
        restoreAll()
        Config.HitboxMode = v
        if v == "Proxy" then
            Notify("Mode", "Proxy — welded, massless, unanchored part, re-sized every frame. Try this if Resize won't register.", 5)
        else
            Notify("Mode", "Resize — real part, locked full-size every frame. The proven method; shots register, no freeze.", 5)
        end
    end)

    UI.Slider(s, "Hitbox Size", 1, 60, Config.HitboxSize, 1, " studs", function(v)
        Config.HitboxSize = v
        table.clear(Hitbox.Expanded)
    end)
    UI.Slider(s, "Transparency", 0, 1, Config.HitboxTrans, 2, "", function(v) Config.HitboxTrans = v end)

    UI.Dropdown(s, "Target Part", PART_LIST, Config.HitboxPart, function(v)
        restoreAll()
        Config.HitboxPart = v
    end)
    UI.Dropdown(s, "Material", {"ForceField", "Neon", "SmoothPlastic", "Glass", "Plastic"}, Config.HitboxMaterial, function(v)
        Config.HitboxMaterial = v
    end)
    UI.Slider(s, "Refresh Rate", 0.03, 1, Config.HitboxRefresh, 2, "s", function(v) Config.HitboxRefresh = v end)

    local s2 = UI.Section(TabHit, "Safety Logic", "stop wasting rounds on bodies that can't be hit")
    UI.Toggle(s2, "Dead Check (shrink hitbox on death)", Config.DeadCheck, function(v)
        Config.DeadCheck = v
        Notify("Dead Check", v and "Corpse hitboxes collapse instantly." or "Off — dead bodies will eat your bullets.", 3, v and nil or "warn")
    end)
    UI.Toggle(s2, "Count K.O. / Knocked as dead", Config.KOCheck, function(v) Config.KOCheck = v end)
    UI.Toggle(s2, "Team Check (skip teammates)", Config.TeamCheck, function(v) Config.TeamCheck = v end)
    UI.Toggle(s2, "Smooth Resize (costs physics churn)", Config.HitboxSmooth, function(v)
        Config.HitboxSmooth = v
        table.clear(Hitbox.Expanded)
    end)
    UI.Toggle(s2, "Massless", Config.HitboxMassless, function(v)
        Config.HitboxMassless = v
        table.clear(Hitbox.Expanded)
    end)

    local s6 = UI.Section(TabHit, "Coverage", "live count of who is actually getting an expanded hitbox")
    -- drives its own color (green at full coverage, amber otherwise), so it
    -- must not be tugged back to Theme.Sub on every theme swap
    HitboxStatus = unthemed(UI.Label(s6, "hitbox is off"))

    UI.Toggle(s6, "Release On Grab (stops carry freezing)", Config.ReleaseOnGrab, function(v)
        Config.ReleaseOnGrab = v
        Notify("Carry", v and "Proxy drops while someone is carried, rebuilds on release."
                          or "Off — an anchored proxy inside a carried character will freeze both players.",
               v and 3 or 4.5, v and nil or "warn")
    end)

    UI.Toggle(s6, "Joint Guard (cut welds on our part)", Config.JointGuard, function(v)
        Config.JointGuard = v
        Notify("Carry", v and "Any joint attached to a proxy gets cut on sight."
                          or "Off — the game can weld our part into a player's assembly.",
               v and 3 or 4.5, v and nil or "warn")
    end)

    UI.Toggle(s6, "FORCE ALL — fight the whole server", Config.ForceAll, function(v)
        Config.ForceAll = v
        if v then Config.WhitelistMode = "Everyone" end   -- ForceAll == Everyone; never overrides a restrictive mode
        restoreAll()
        Notify("Force All", v and "Everyone is a target. (Sets Targets mode to Everyone.)"
                            or "Off — your Targets tab mode (Selected / Blacklist) now decides who you fight.", 4)
    end)

    -- per-player ledger: whatever the sweep decided, it is shown here by name
    HitboxReport = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 190), BackgroundColor3 = Theme.Card,
        ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = s6,
    })
    corner(HitboxReport, 8); themed(HitboxReport, "BackgroundColor3", "Card")
    themed(HitboxReport, "ScrollBarImageColor3", "Accent")
    pad(HitboxReport, 8, 8, 6, 6)
    new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = HitboxReport})

    UI.Toggle(s6, "Part Fallback (R15 rigs + missing limbs)", Config.PartFallback, function(v)
        Config.PartFallback = v
        restoreAll()
        Notify("Coverage", v and "Missing parts now resolve to a rig equivalent or the root."
                            or "Strict mode — exact part name only.", 3)
    end)

    UI.Button(s6, "Force Re-Apply to Everyone", function()
        table.clear(Hitbox.Expanded)
        table.clear(Hitbox.Settle)
        Notify("Coverage", "Memo cleared. Every target re-expands on the next sweep.", 2.8)
    end)

    local s5 = UI.Section(TabHit, "Physics Load", "if remote players stop moving, this is the dial")

    UI.Toggle(s5, "Low Impact Mode (fixes frozen players)", Config.LowImpact, function(v)
        Config.LowImpact = v
        restoreAll()
        Notify("Physics", v and "Massless + Material writes disabled. Size and collision only."
                            or "Full property set re-enabled.", 3.2)
    end)

    UI.Label(s5, "Every property is now written only when its value actually differs. Massless and Material each force a mass-property recompute on the target's assembly — writing them on a loop stalls their replicated movement. Low Impact skips both outright.")

    local s4 = UI.Section(TabHit, "Collision", "Proxy mode is already non-solid — these only apply to Resize mode")

    UI.Dropdown(s4, "Proxy Part Name", {"HumanoidRootPart", "Torso", "Head", "MoneyHitbox"}, Config.ProxyName, function(v)
        Config.ProxyName = v
        destroyAllProxies()
        Notify("Proxy", "Proxies renamed to '" .. v .. "' and rebuilt. Change this only if hits stop registering.", 4)
    end)

    UI.Toggle(s4, "Ghost Downed Bodies (walk through ragdolls)", Config.GhostDowned, function(v)
        Config.GhostDowned = v
        if not v then unghostAll() end
        Notify("Collision", v and "Knocked players' own limbs are now non-solid. Restored on revive."
                              or "Downed bodies are solid again.", 3.2)
    end)

    UI.Toggle(s4, "Phase Through (Resize mode only)", Config.PhaseThrough, function(v)
        Config.PhaseThrough = v
        if not v then
            table.clear(Hitbox.Expanded)
            Notify("Collision", "Phase off — expanded parts are solid again.", 3, "warn")
        else
            Notify("Collision", "Phasing on. CanCollide cleared every physics frame.", 2.8)
        end
    end)

    UI.Toggle(s4, "Disable Touch Events", Config.NoTouch, function(v)
        Config.NoTouch = v
        if not v then restoreAll() end
        Notify("Collision", v and "Touched events killed on expanded parts."
                              or "Touch events restored.", 2.6)
    end)

    UI.Toggle(s4, "Can Collide (ignored while phasing)", Config.HitboxCollide, function(v)
        Config.HitboxCollide = v
        if v and Config.PhaseThrough then
            Notify("Collision", "Turn Phase Through off first — it overrides this.", 3.5, "warn")
        end
    end)

    UI.Label(s4, "Phasing only clears collision. CanQuery is left alone, so bullets still raycast against the full expanded volume — you lose the wall, not the hitbox.")

    local s3 = UI.Section(TabHit, "Quick Actions")
    UI.Button(s3, "Restore All Hitboxes Now", function()
        restoreAll()
        Notify("Restore", "Every cached part returned to original size.", 2.5)
    end)
    UI.Button(s3, "Reset to Defaults", function()
        Config.HitboxSize, Config.HitboxTrans, Config.HitboxPart = 12, 0.65, "HumanoidRootPart"
        restoreAll()
        Notify("Reset", "Hitbox settings back to stock. Reopen the tab to refresh sliders.", 3)
    end)
end

local function buildTrigger()
    local s = UI.Section(TabTrigger, "Triggerbot", "auto-fires the instant an enemy crosses your cursor")

    -- drives its own status text; don't let a theme swap tug it back to Sub
    TriggerStatus = unthemed(UI.Label(s, "triggerbot is off"))

    UI.Toggle(s, "Enable Triggerbot", Config.TriggerEnabled, function(v)
        Config.TriggerEnabled = v
        if v then startTrigger() end
        if TriggerStatus then
            TriggerStatus.Text = v and "armed — put an enemy under your cursor" or "triggerbot is off"
        end
        Notify("Triggerbot", v and ("Armed. Delay " .. Config.TriggerDelay .. "ms · rate " .. Config.TriggerRate .. "ms.")
                              or "Disarmed.", 3)
    end)

    -- the two scales you asked for
    UI.Slider(s, "Trigger Delay", 0, 500, Config.TriggerDelay, 0, " ms", function(v)
        Config.TriggerDelay = v
    end)
    UI.Slider(s, "Fire Rate  (gap between shots)", 10, 1000, Config.TriggerRate, 0, " ms", function(v)
        Config.TriggerRate = v
    end)
    UI.Slider(s, "Max Distance", 10, 2000, Config.TriggerMaxDist, 0, " studs", function(v)
        Config.TriggerMaxDist = v
    end)

    local s2 = UI.Section(TabTrigger, "Filters", "who and when it's allowed to pull the trigger")
    UI.Toggle(s2, "Only Fire At My Targets (Targets tab)", Config.TriggerRespectWL, function(v)
        Config.TriggerRespectWL = v
        Notify("Triggerbot", v and "Now only fires at players allowed by the Targets tab (Selected/Blacklist)."
                              or "Off — will fire at anyone under the cursor, ignoring the Targets list.", 4, v and nil or "warn")
    end)
    UI.Toggle(s2, "Skip Downed / Dead", Config.TriggerDeadCheck, function(v) Config.TriggerDeadCheck = v end)
    UI.Toggle(s2, "Team Check (skip teammates)", Config.TriggerTeamCheck, function(v) Config.TriggerTeamCheck = v end)
    UI.Toggle(s2, "Wall Check (line of sight only)", Config.TriggerWallCheck, function(v)
        Config.TriggerWallCheck = v
        Notify("Triggerbot", v and "Won't fire through walls." or "Wall check off — will fire at anything under the cursor.", 3)
    end)
    UI.Toggle(s2, "Only Fire With A Gun Equipped", Config.TriggerGunOnly, function(v) Config.TriggerGunOnly = v end)

    local s3 = UI.Section(TabTrigger, "Activation", "always-on, or only while a key is held")
    UI.Toggle(s3, "Hold Key To Fire  (off = always active)", Config.TriggerHoldMode, function(v)
        Config.TriggerHoldMode = v
        Notify("Triggerbot", v and "Now only fires while the hold key is down." or "Always active while enabled.", 3)
    end)
    UI.Keybind(s3, "Hold Key", Config.TriggerKey, function(k) Config.TriggerKey = k end)

    UI.Label(s3, "Zero delay by default: the loop runs every frame, so with Trigger Delay at 0 it fires the same frame an enemy touches your cursor. Raise Fire Rate's ms to slow the spam, lower it to dump faster. Pair it with the Resize hitbox for the widest, most reliable hits.")
end

safeBuild("Targets", function()
    local s = UI.Section(TabTarget, "Targeting Mode", "who the hitbox and esp actually apply to")
    UI.Dropdown(s, "Mode", {"Everyone", "Selected", "Blacklist"}, Config.WhitelistMode, function(v)
        Config.WhitelistMode = v
        if v == "Selected" then
            -- fresh slate: YOU pick who to fight. Kill the auto-fill + force-all so
            -- they can't silently re-add the whole server behind your back.
            Config.ForceAll = false
            Config.AutoWhitelist = false
            table.clear(Config.Whitelisted)
        elseif v == "Blacklist" then
            Config.ForceAll = false
            Config.AutoWhitelist = false
            table.clear(Config.Blacklisted)
        end
        restoreAll()
        if RefreshList then pcall(RefreshList) end
        local msg = (v == "Everyone" and "Every player is a target (hitbox + triggerbot).")
                 or (v == "Selected" and "Fresh list — ONLY players you add are targets. Add them on the Player List below.")
                 or "Everyone EXCEPT the ones you add. Add people to ignore on the Player List below."
        Notify("Mode", msg, 4)
    end)
    UI.Toggle(s, "Auto-Whitelist Everyone Who Joins", Config.AutoWhitelist, function(v)
        Config.AutoWhitelist = v
        if v then
            local n = 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    Config.Whitelisted[p.UserId] = true
                    Config.Blacklisted[p.UserId] = nil
                    n = n + 1
                end
            end
            if RefreshList then pcall(RefreshList) end
            Notify("Auto-Whitelist", "On. " .. n .. " players marked, joiners added automatically.", 3.2)
        else
            Notify("Auto-Whitelist", "Off. New joiners will not be targeted.", 2.8)
        end
    end)

    UI.Button(s, "Select ALL players", function()
        local n = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then Config.Whitelisted[p.UserId] = true; n = n + 1 end
        end
        if RefreshList then pcall(RefreshList) end
        Notify("Whitelist", n .. " players marked as targets.", 2.8)
    end)
    UI.Button(s, "Clear selection", function()
        table.clear(Config.Whitelisted)
        table.clear(Config.Blacklisted)
        restoreAll()
        if RefreshList then pcall(RefreshList) end
        Notify("Whitelist", "Selection cleared.", 2.4)
    end)

    local s2 = UI.Section(TabTarget, "Player List", "3D loads them into the 4D display  •  add marks them a target")
    buildPlayerList(s2)
    UI.Button(s2, "Refresh List", function()
        pcall(RefreshList)
        Notify("List", "Player list rebuilt.", 2)
    end)
end)

local function buildEsp()
    local s = UI.Section(TabEsp, "ESP Core", "profile-picture tags or the full cinematic overlay")
    UI.Toggle(s, "Enable ESP", Config.EspEnabled, function(v)
        Config.EspEnabled = v
        if not v then for _, o in pairs(Esp.Objects) do hideEsp(o) end end
        Notify("ESP", v and ("Rendering in " .. Config.EspStyle .. " mode.") or "ESP off.", 2.6)
    end)
    EspStatus = unthemed(UI.Label(s, "esp is off"))

    UI.Dropdown(s, "Display Style", {"Profile", "Cinematic", "Both"}, Config.EspStyle, function(v) Config.EspStyle = v end)
    UI.Slider(s, "Avatar Size", 24, 90, Config.EspAvatarSize, 0, "px", function(v) Config.EspAvatarSize = v end)
    UI.Slider(s, "Max Distance", 100, 5000, Config.EspMaxDistance, 0, "m", function(v) Config.EspMaxDistance = v end)
    UI.Slider(s, "Update Rate", 15, 144, Config.EspRate, 0, " fps", function(v) Config.EspRate = v end)

    local s2 = UI.Section(TabEsp, "Cinematic Layer")
    UI.Toggle(s2, "Boxes", Config.EspBox, function(v) Config.EspBox = v end)
    UI.Dropdown(s2, "Box Style", {"Corner", "Full", "Glow"}, Config.EspBoxStyle, function(v) Config.EspBoxStyle = v end)
    UI.Toggle(s2, "Names", Config.EspName, function(v) Config.EspName = v end)
    UI.Toggle(s2, "Health Bars", Config.EspHealth, function(v) Config.EspHealth = v end)
    UI.Toggle(s2, "Distance", Config.EspDistance, function(v) Config.EspDistance = v end)
    UI.Toggle(s2, "Held Tool", Config.EspTool, function(v) Config.EspTool = v end)
    UI.Toggle(s2, "Chams (through walls)", Config.EspChams, function(v) Config.EspChams = v end)
    UI.Toggle(s2, "Off-screen Arrows", Config.EspArrows, function(v)
        Config.EspArrows = v
        if not v then for _, o in pairs(Esp.Objects) do o.Arrow.Visible = false end end
    end)

    local s3 = UI.Section(TabEsp, "Tracers")
    UI.Toggle(s3, "Enable Tracers", Config.EspTracer, function(v)
        Config.EspTracer = v
        if not v then for _, o in pairs(Esp.Objects) do o.Tracer.Visible = false end end
    end)
    UI.Dropdown(s3, "Origin", {"Bottom", "Center", "Mouse"}, Config.EspTracerFrom, function(v) Config.EspTracerFrom = v end)

    local s4 = UI.Section(TabEsp, "Color Behaviour")
    UI.Toggle(s4, "Rainbow Cycle", Config.EspRainbow, function(v) Config.EspRainbow = v end)
    UI.Toggle(s4, "Use Team Colors", Config.EspTeamColor, function(v) Config.EspTeamColor = v end)
    UI.Toggle(s4, "Fade Dead Players", Config.EspDeadFade, function(v) Config.EspDeadFade = v end)
end

safeBuild("4D Display", function()
    local s = UI.Section(TabPrev, "4D Character Display",
        "a live clone orbiting on three axes with a drifting fourth — every ESP setting renders here first")
    buildPreview(s)

    local s2 = UI.Section(TabPrev, "Display Controls")
    UI.Button(s2, "Load My Character", function()
        if loadPreviewModel(LocalPlayer) then
            Notify("Preview", "Your character is on the turntable.", 2.4)
        else
            Notify("Preview", "No character to clone yet.", 2.4, "warn")
        end
    end)
    UI.Button(s2, "Load Nearest Player", function()
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then Notify("Preview", "You have no character right now.", 2.4, "bad") return end
        local best, bd = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            local r = p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local d = (r.Position - myRoot.Position).Magnitude
                if d < bd then best, bd = p, d end
            end
        end
        if best and loadPreviewModel(best) then
            Notify("Preview", best.DisplayName .. " loaded — " .. math.floor(bd) .. "m away.", 2.6)
        else
            Notify("Preview", "Nobody nearby to load.", 2.4, "warn")
        end
    end)
    UI.Toggle(s2, "Auto Spin", true, function(v) Preview.Spin = v end)
    UI.Slider(s2, "Preview Avatar Size", 24, 90, Config.EspAvatarSize, 0, "px", function(v) Config.EspAvatarSize = v end)
end)

safeBuild("Themes", function()
    local s = UI.Section(TabTheme, "Themes", "24 palettes — every panel, stroke and esp accent follows instantly")
    -- deferred one frame so 24 swatch cards don't build on the inject frame
    task.defer(buildThemeGrid, s)
end)

local function buildSettings()
    local s = UI.Section(TabSet, "Interface")
    UI.Keybind(s, "Toggle Menu", Config.Keybind, function(k)
        Config.Keybind = k
        Notify("Keybind", "Menu bound to " .. k.Name .. ".", 2.4)
    end)
    UI.Slider(s, "UI Scale", 0.7, 1.4, Config.UIScale, 2, "x", function(v)
        Config.UIScale = v
        UIScaler.Scale = v
    end)
    UI.Toggle(s, "Watermark", Config.Watermark, function(v)
        Config.Watermark = v
        Watermark.Visible = v
    end)

    local s2 = UI.Section(TabSet, "Session")
    UI.Label(s2, "Hitboxes restore automatically on unload, on death, on K.O., and when a target leaves the server.")
    UI.Button(s2, "Panic — restore everything & hide", function()
        Config.HitboxEnabled = false
        Config.EspEnabled = false
        restoreAll()
        for _, o in pairs(Esp.Objects) do hideEsp(o) end
        Main.Visible = false
        Watermark.Visible = false
        closeAllMenus()
    end)
    UI.Button(s2, "Unload MoneyWare", function()
        if getgenv and getgenv().MoneyWareUnload then getgenv().MoneyWareUnload() end
    end)

    local s3 = UI.Section(TabSet, "Credits")
    UI.Label(s3, "MoneyWare v2.0 — built for Larpbase. Presets live in the Config tab; original part properties are cached before anything is touched, so nothing stays broken when you leave.")
end

local function buildConfig()
    local s = UI.Section(TabCfg, "Config Manager", "save your entire setup and load it back in one click")

    local fsLabel = unthemed(UI.Label(s, ConfigIO.HasFS()
        and ("file system ready  ·  presets → " .. CFG_FOLDER)
        or  "no file system on this host — use Copy / Import below"))
    fsLabel.TextColor3 = ConfigIO.HasFS() and C3(90, 230, 140) or C3(255, 190, 80)
    fsLabel.Font = Enum.Font.Code

    -- name + save
    local nameRow = new("Frame", {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Card, Parent = s})
    corner(nameRow, 9); themed(nameRow, "BackgroundColor3", "Card")
    local nameBox = new("TextBox", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -116, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 13, PlaceholderText = "name this preset...", Text = "",
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = nameRow,
    })
    themed(nameBox, "TextColor3", "Text"); themed(nameBox, "PlaceholderColor3", "Sub")
    local saveBtn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 96, 0, 28),
        BackgroundColor3 = Theme.Accent, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 12.5,
        Text = "SAVE", TextColor3 = C3(255, 255, 255), Parent = nameRow,
    })
    corner(saveBtn, 8); themed(saveBtn, "BackgroundColor3", "Accent")
    do local _, g = gStroke(saveBtn, Theme.Accent, Theme.Accent2, 1, 0.2)
       onThemeRefresh(function() g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end) end

    local s2 = UI.Section(TabCfg, "Saved Presets", "load applies live — sliders, toggles, theme, all of it")
    local listHolder = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 208), BackgroundColor3 = Theme.Card, ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = s2,
    })
    corner(listHolder, 9); themed(listHolder, "BackgroundColor3", "Card"); themed(listHolder, "ScrollBarImageColor3", "Accent")
    pad(listHolder, 8, 8, 8, 8)
    new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listHolder})

    local function refreshList()
        for _, ch in ipairs(listHolder:GetChildren()) do if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end end
        local names = ConfigIO.List()
        if #names == 0 then
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
                Text = ConfigIO.HasFS() and "  no presets yet — save one above" or "  file system unavailable — use Copy Config",
                TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left, Parent = listHolder,
            })
            return
        end
        local auto = ConfigIO.GetAutoload()
        for _, nm in ipairs(names) do
            local active = (nm == Config.ActivePreset)
            local row = new("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.Panel, Parent = listHolder})
            corner(row, 8); themed(row, "BackgroundColor3", "Panel")
            if active then local _, g = gStroke(row, Theme.Accent, Theme.Accent2, 1.2, 0.2)
                onThemeRefresh(function() g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2) end) end

            local nlbl = new("TextLabel", {
                Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -180, 1, 0), BackgroundTransparency = 1,
                Font = active and Enum.Font.GothamBold or Enum.Font.GothamSemibold, TextSize = 13,
                Text = nm .. ((nm == auto) and "   · auto" or ""), TextColor3 = active and Theme.Accent or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
            })

            local delB = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 28, 0, 26),
                BackgroundColor3 = C3(48, 20, 26), AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 12,
                Text = "×", TextColor3 = C3(255, 120, 140), Parent = row,
            })
            corner(delB, 7)
            local autoB = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -44, 0.5, 0), Size = UDim2.new(0, 54, 0, 26),
                BackgroundColor3 = Theme.Card, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 10.5,
                Text = (nm == auto) and "AUTO" or "auto", TextColor3 = (nm == auto) and C3(90, 230, 140) or Theme.Sub, Parent = row,
            })
            corner(autoB, 7); themed(autoB, "BackgroundColor3", "Card")
            local loadB = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -104, 0.5, 0), Size = UDim2.new(0, 62, 0, 26),
                BackgroundColor3 = Theme.Accent, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 11.5,
                Text = "LOAD", TextColor3 = C3(255, 255, 255), Parent = row,
            })
            corner(loadB, 7); themed(loadB, "BackgroundColor3", "Accent")

            loadB.MouseButton1Click:Connect(function()
                local ok, err = ConfigIO.Load(nm)
                if ok then Notify("Config", "Loaded '" .. nm .. "' — everything updated.", 3)
                else Notify("Config", "Load failed: " .. tostring(err), 3, "warn") end
                task.defer(refreshList)
            end)
            delB.MouseButton1Click:Connect(function()
                if ConfigIO.Delete(nm) then Notify("Config", "Deleted '" .. nm .. "'.", 2.4); refreshList()
                else Notify("Config", "Couldn't delete (no file system?).", 2.8, "warn") end
            end)
            autoB.MouseButton1Click:Connect(function()
                if ConfigIO.GetAutoload() == nm then
                    ConfigIO.SetAutoload(nil); Notify("Autoload", "Cleared — nothing loads on inject.", 2.6)
                else
                    ConfigIO.SetAutoload(nm); Notify("Autoload", "'" .. nm .. "' will load automatically on inject.", 3)
                end
                refreshList()
            end)
        end
    end

    saveBtn.MouseButton1Click:Connect(function()
        local nm = nameBox.Text
        if nm == "" then nm = "preset_" .. tostring(#ConfigIO.List() + 1) end
        local ok, res = ConfigIO.Save(nm)
        if ok then
            nameBox.Text = ""
            Notify("Config", "Saved preset '" .. res .. "'.", 2.6)
            refreshList()
        else
            Notify("Config", "Save failed: " .. tostring(res), 3, "warn")
        end
    end)

    local s3 = UI.Section(TabCfg, "Share / Backup", "move presets between hosts through the clipboard")
    UI.Button(s3, "Copy Current Config to Clipboard", function()
        local ok = ConfigIO.Export()
        Notify("Config", ok and "Copied current config to clipboard as JSON." or "Copy failed.", 2.8, ok and nil or "warn")
    end)
    local pasteRow = new("Frame", {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Card, Parent = s3})
    corner(pasteRow, 9); themed(pasteRow, "BackgroundColor3", "Card")
    local pasteBox = new("TextBox", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -116, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12.5, PlaceholderText = "paste config JSON here...", Text = "",
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = pasteRow,
    })
    themed(pasteBox, "TextColor3", "Text"); themed(pasteBox, "PlaceholderColor3", "Sub")
    local impBtn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 96, 0, 28),
        BackgroundColor3 = Theme.Accent, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 12.5,
        Text = "IMPORT", TextColor3 = C3(255, 255, 255), Parent = pasteRow,
    })
    corner(impBtn, 8); themed(impBtn, "BackgroundColor3", "Accent")
    impBtn.MouseButton1Click:Connect(function()
        local ok, err = ConfigIO.Import(pasteBox.Text)
        if ok then pasteBox.Text = ""; Notify("Config", "Imported & applied.", 2.8); task.defer(refreshList)
        else Notify("Config", "Import failed: " .. tostring(err), 3, "warn") end
    end)
    UI.Button(s3, "Reset All Settings to Defaults", function()
        if ConfigIO.Reset() then Notify("Config", "Everything reset to stock defaults.", 2.8) task.defer(refreshList)
        else Notify("Config", "Couldn't reset.", 2.6, "warn") end
    end)

    refreshList()
end

--============================================================================--
--  19.5 BUILD THE SETTINGS TABS  (+ live-rebuild hook for preset loads)
--============================================================================--

safeBuild("Hitbox",     buildHitbox)
safeBuild("Triggerbot", buildTrigger)
safeBuild("ESP",        buildEsp)
safeBuild("Config",     buildConfig)
safeBuild("Settings",   buildSettings)

-- fills the forward-declared local from section 18.5 so ConfigIO.Load can
-- regenerate every settings widget straight from the freshly-loaded Config
rebuildSettingsTabs = function()
    local function clearPage(tab)
        for _, ch in ipairs(tab.Page:GetChildren()) do
            if ch:IsA("Frame") then ch:Destroy() end
        end
        for i = #ThemedObjects, 1, -1 do
            if not ThemedObjects[i].inst or not ThemedObjects[i].inst.Parent then table.remove(ThemedObjects, i) end
        end
    end
    clearPage(TabHit);     safeBuild("Hitbox",     buildHitbox)
    clearPage(TabTrigger); safeBuild("Triggerbot", buildTrigger)
    clearPage(TabEsp);     safeBuild("ESP",        buildEsp)
    clearPage(TabSet);     safeBuild("Settings",   buildSettings)
end

--============================================================================--
--  20. WINDOW STATE + KEYBIND
--============================================================================--

local uiOpen, minimized = true, false

local function setOpen(v)
    uiOpen = v
    closeAllMenus()
    if v then
        Main.Visible = true
        Main.Size = UDim2.new(0, WIN_W * 0.93, 0, (minimized and 52 or WIN_H) * 0.93)
        tween(Main, 0.28, {Size = UDim2.new(0, WIN_W, 0, minimized and 52 or WIN_H)})
    else
        tween(Main, 0.2, {Size = UDim2.new(0, WIN_W * 0.94, 0, (minimized and 52 or WIN_H) * 0.94)})
        task.delay(0.22, function() if not uiOpen and Main then Main.Visible = false end end)
    end
end

CloseBtn.MouseButton1Click:Connect(function() setOpen(false) end)
CloseBtn.MouseEnter:Connect(function() tween(CloseBtn, 0.14, {BackgroundColor3 = C3(200,50,70), TextColor3 = C3(255,255,255)}) end)
CloseBtn.MouseLeave:Connect(function() tween(CloseBtn, 0.14, {BackgroundColor3 = Theme.Card, TextColor3 = Theme.Sub}) end)

MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    closeAllMenus()
    tween(Main, 0.25, {Size = UDim2.new(0, WIN_W, 0, minimized and 52 or WIN_H)})
end)

bind(UserInputService.InputBegan, function(i, gpe)
    if i.UserInputType ~= Enum.UserInputType.Keyboard then return end

    -- rebinding takes priority over toggling
    for _, fn in ipairs(KeybindListeners) do
        if fn(i.KeyCode) then return end
    end

    if gpe then return end
    if i.KeyCode == Config.Keybind then setOpen(not uiOpen) end
end)

--============================================================================--
--  21. RENDER LOOP  (throttled, budgeted, fully guarded)
--============================================================================--

local espAcc, wmAcc, frames, fps = 0, 0, 0, 60
local uiClock = 0

bind(RunService.RenderStepped, function(dt)
    frames = frames + 1
    wmAcc  = wmAcc + dt
    espAcc = espAcc + dt

    -- pump living-UI animation. The watermark HUD is always visible, so its
    -- handful of tiny anims run every frame; the whole window backdrop only
    -- animates while the menu is actually shown, so a CLOSED menu adds nothing
    -- on top of your Zee Hood frame. This is the main anti-lag lever.
    uiClock = uiClock + dt
    pcall(pumpList, AnimWM, uiClock, dt)
    if Main.Visible and not minimized then
        pcall(pumpList, AnimWin, uiClock, dt)
    end

    local interval = 1 / math.clamp(Config.EspRate, 15, 144)
    if espAcc >= interval then
        espAcc = 0
        local ok, err = pcall(updateEsp)
        if not ok then warn("[MoneyWare] esp: " .. tostring(err)) end
    end

    -- proxies follow on the render frame so they line up with what you aim at
    local okP, errP = pcall(updateProxies)
    if not okP then warn("[MoneyWare] proxy: " .. tostring(errP)) end

    local ok2, err2 = pcall(updatePreview, dt)
    if not ok2 then warn("[MoneyWare] preview: " .. tostring(err2)) end

    if wmAcc >= 0.5 then
        fps = math.floor(frames / wmAcc)
        frames, wmAcc = 0, 0

        if HitboxStatus and HitboxStatus.Parent then
            if not Config.HitboxEnabled then
                HitboxStatus.Text = "hitbox is off"
                HitboxStatus.TextColor3 = Theme.Sub
            else
                local st = Hitbox.Stats
                -- eligible = everyone we could legitimately cover right now
                local eligible = st.total - st.filtered - st.down - st.carried
                local pct = (eligible > 0) and math.floor(st.applied / eligible * 100 + 0.5) or 100

                local bits = {("%s  ·  %d / %d covered  ·  %d%%"):format(
                    Config.HitboxMode, st.applied, math.max(eligible, 0), pct)}
                if st.down     > 0 then table.insert(bits, st.down .. " down") end
                if st.carried  > 0 then table.insert(bits, st.carried .. " carried") end
                if st.filtered > 0 then table.insert(bits, st.filtered .. " filtered") end
                if st.nochar   > 0 then table.insert(bits, st.nochar .. " loading") end
                if st.nopart   > 0 then
                    table.insert(bits, st.nopart .. (Config.HitboxMode == "Proxy"
                        and " no usable part" or (" missing '" .. Config.HitboxPart .. "'")))
                end

                HitboxStatus.Text = table.concat(bits, "   |   ")
                HitboxStatus.TextColor3 = (pct >= 100 and st.nochar == 0 and st.nopart == 0)
                    and C3(90, 230, 140) or C3(255, 190, 80)
            end
        end

        if EspStatus and EspStatus.Parent then
            if not Config.EspEnabled then
                EspStatus.Text = "esp is off"
                EspStatus.TextColor3 = Theme.Sub
            else
                local bits = {("drawn %d / %d eligible"):format(Esp.Drawn, Esp.Eligible)}
                local hidden = Esp.Eligible - Esp.Drawn - Esp.Errors
                if hidden > 0 then table.insert(bits, hidden .. " out of range / down") end
                if Esp.Errors > 0 then table.insert(bits, Esp.Errors .. " ERRORED") end
                EspStatus.Text = table.concat(bits, "   |   ")
                EspStatus.TextColor3 = (Esp.Errors > 0) and C3(255, 120, 90)
                    or ((Esp.Drawn > 0 or Esp.Eligible == 0) and C3(90, 230, 140) or C3(255, 190, 80))
            end
        end

        -- per-player ledger, only while its tab is actually on screen
        if HitboxReport and HitboxReport.Parent and CurrentTab and CurrentTab.Name == "Hitbox" then
            for _, ch in ipairs(HitboxReport:GetChildren()) do
                if ch:IsA("Frame") then ch:Destroy() end
            end
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local status = Hitbox.Report[plr] or (Config.HitboxEnabled and "pending" or "idle")
                    local good   = (status:sub(1, 7) == "covered")
                    local neutral = (status == "down" or status == "filtered"
                                  or status == "idle" or status == "carried")

                    local row = new("Frame", {
                        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = HitboxReport,
                    })
                    -- colour set directly, NOT via themed(): these rows are
                    -- rebuilt twice a second and would flood ThemedObjects
                    new("TextLabel", {
                        Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1,
                        Font = Enum.Font.Gotham, TextSize = 11, Text = plr.DisplayName,
                        TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
                    })
                    new("TextLabel", {
                        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
                        Size = UDim2.new(0, 106, 1, 0), BackgroundTransparency = 1,
                        Font = Enum.Font.GothamBold, TextSize = 10.5, Text = status,
                        TextXAlignment = Enum.TextXAlignment.Right,
                        TextColor3 = good and C3(90, 230, 140)
                                  or (neutral and C3(140, 140, 155) or C3(255, 120, 90)),
                        Parent = row,
                    })
                end
            end
        end

        if Config.Watermark and Watermark.Visible then
            local ping = 0
            pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
            local targets = 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and Whitelist.IsTarget(p) and not isDead(p) then targets = targets + 1 end
            end
            WmText.Text = string.format("%dfps · %dms · %d alive · %s",
                fps, ping, targets, Config.HitboxEnabled and "HB" or "—")
        end
    end
end)

--============================================================================--
--  22. UNLOAD
--============================================================================--

local function unload()
    Alive = false
    Config.HitboxEnabled = false
    Config.EspEnabled = false

    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Connections)

    restoreAll()          -- restores resized parts AND destroys every proxy
    destroyAllProxies()   -- belt and braces if restoreAll was short-circuited

    -- snapshot the keys; never mutate a table mid-pairs
    local players = {}
    for plr in pairs(Esp.Objects) do table.insert(players, plr) end
    for _, plr in ipairs(players) do destroyEsp(plr) end

    if Preview.Model then pcall(function() Preview.Model:Destroy() end) end
    pcall(function() ScreenGui:Destroy() end)

    if getgenv then
        getgenv().MoneyWareLoaded = false
        getgenv().MoneyWareUnload = nil
    end
end

if getgenv then
    getgenv().MoneyWareLoaded = true
    getgenv().MoneyWareUnload = unload
end

-- 4D preview loads lazily the first time you open its tab (see updatePreview),
-- so nothing is cloned and no ViewportFrame renders on inject. On respawn the
-- old clone goes stale and is rebuilt automatically next time you view the tab.
bind(LocalPlayer.CharacterAdded, function()
    if Preview.Model then pcall(function() Preview.Model:Destroy() end); Preview.Model = nil end
end)

--============================================================================--
--  23. SELF TEST
--============================================================================--

-- spring intro: the window pops in from slightly under-scale on load
task.spawn(function()
    if not Main or not Main.Parent then return end
    Main.Size = UDim2.new(0, math.floor(WIN_W * 0.9), 0, math.floor(WIN_H * 0.9))
    spring(Main, 0.55, {Size = UDim2.new(0, WIN_W, 0, WIN_H)})
end)

task.spawn(function()
    task.wait(0.2)
    local problems = {}
    if not ScreenGui.Parent then table.insert(problems, "gui not parented") end
    if #Tabs < 8 then table.insert(problems, ("only %d/8 tabs built"):format(#Tabs)) end
    if not Preview.Vp then table.insert(problems, "preview missing") end

    if #problems > 0 then
        warn("[MoneyWare] self-test: " .. table.concat(problems, ", "))
        Notify("Self-test", table.concat(problems, ", "), 6, "bad")
    else
        Notify("MoneyWare v2.0 loaded", "All 8 tabs built clean. RightShift toggles the menu — presets live in the Config tab.", 5)
    end
end)

-- autoload: pull the flagged preset the moment we're up
task.spawn(function()
    task.wait(0.7)
    local auto = ConfigIO.GetAutoload()
    if auto then
        local ok = ConfigIO.Load(auto)
        if ok then Notify("Autoload", "Loaded preset '" .. auto .. "'.", 3.5) end
    end
end)