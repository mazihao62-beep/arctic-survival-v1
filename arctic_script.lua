--[[
    北极生存7天 - 自动收集物资 v2.2
    Auger挖雪(走到挖掘点) + ByteNet砍树 + 拖动回家
    每个功能单独循环，不抢工具
    改进工具检测：打印所有已找到的工具名
    修复：先弹Popup确认后才创建窗口
--]]

print("[北极] v2.2 加载中...")

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")
local C = game:GetService("CoreGui")

local LP = P.LocalPlayer
if not LP then return end
print("[北极] 玩家: " .. LP.Name)

-- 清理旧Gui
for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") and (g.Name:find("Arctic") or g.Name == "WindUI") then
        pcall(function() g:Destroy() end)
    end
end

-- 加载WindUI (三路)
print("[北极] 加载WindUI...")
local WI = nil
local function tryLoad()
    local ok1, s1 = pcall(function() return readfile("windui_source.lua") end)
    if ok1 and s1 and #s1 > 100 then
        local ok, m = pcall(loadstring, s1)
        if ok and m then local ok2, i = pcall(m); if ok2 and i then return i end end
    end
    for i = 1, 3 do
        local ok, s2 = pcall(function() return game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua") end)
        if ok and s2 and #s2 > 100 then
            local ok, m = pcall(loadstring, s2)
            if ok and m then local ok2, i = pcall(m); if ok2 and i then return i end end
        end
        if i < 3 then wait(1) end
    end
    return nil
end
WI = tryLoad()
print("[北极] WindUI=" .. (WI and "OK" or "NIL"))

-- 远程事件
local Rem = RS:FindFirstChild("Remotes")
local RD = Rem and Rem:FindFirstChild("RequestDrag")
local RL = Rem and Rem:FindFirstChild("ReleaseDrag")
local BNR = RS:FindFirstChild("ByteNetReliable")
local BM = pcall(function() return buffer.create end)
print("[北极] 事件: Drag=" .. (RD and "OK" or "NIL") .. " Release=" .. (RL and "OK" or "NIL") .. " ByteNet=" .. (BNR and "OK" or "NIL") .. " Buffer=" .. (BM and "OK" or "NIL"))

-- Cobalt buffers
local sb = {39,108,84,138,63}
local tb = {41,3,0,65,120,101,8,0,65,120,101,83,119,105,110,103,20,1,42,197,127,191,99,221,42,61,220,52,242,59,69,171,14,68,253,170,165,66,172,8,26,68}
local function mkSB() local b=buffer.create(#sb); for i=1,#sb do buffer.writeu8(b,i-1,sb[i]) end; return b end
local function mkTB() local b=buffer.create(#tb); for i=1,#tb do buffer.writeu8(b,i-1,tb[i]) end; return b end

local homePos, WN, CT = nil, nil, {}
local S = {Snow=false, Wood=false, Drag=false, HomeP=nil, Range=60}
local KB = {Toggle="RightShift"}

-- 打印当前所有工具
local function debugTools()
    local all = {}
    local c = LP.Character
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then table.insert(all, "[角色]"..t.Name) end
        end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(all, "[背包]"..t.Name) end
        end
    end
    if #all > 0 then
        print("[调试] 当前工具: " .. table.concat(all, ", "))
    else
        print("[调试] 无工具")
    end
end

spawn(function() wait(3); debugTools() end)

local function getTool(kw)
    for _, src in ipairs({LP.Character, LP:FindFirstChild("Backpack")}) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") then
                    local ln = t.Name:lower()
                    for _, k in ipairs(kw) do
                        if ln:find(k, 1, true) then return t end
                    end
                end
            end
        end
    end
    return nil
end

local function eq(t)
    if not t then return false end
    local c=LP.Character; if not c then return false end
    local h=c:FindFirstChildOfClass("Humanoid"); if not h then return false end
    if t.Parent~=c then h:EquipTool(t); wait(0.3) end; return true
end

local function hrp() local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

-- ===== 挖雪 =====
local function digSnow()
    if not S.Snow or not BNR or not BM then return end
    local auger = getTool({"auger","drill"})
    if not auger then print("[雪] 无Auger"); debugTools(); return end
    eq(auger)
    local things = WS:FindFirstChild("Things")
    local digPoint = things and things:FindFirstChild("DigPoint")
    local digHere = things and things:FindFirstChild("DigHere")
    local h = hrp(); if not h then return end
    local tp = digPoint and digPoint.Position or (digHere and digHere.Position)
    if not tp then print("[雪] 无挖掘点"); return end
    local dist = (tp - h.Position).Magnitude
    if dist > S.Range then print(string.format("[雪] %.1fm > %dm", dist, S.Range)); return end
    print(string.format("[雪] 距离%.1fm 走到挖掘点...", dist))
    h.CFrame = CFrame.new(tp.X, tp.Y + 1, tp.Z)
    wait(0.5)
    local ok, err = pcall(function() BNR:FireServer(mkSB(), nil) end)
    print(ok and "[雪] OK" or ("[雪] 失败:"..tostring(err)))
    wait(1)
end

-- ===== 砍树 =====
local function cutTree()
    if not S.Wood or not BNR or not BM then return end
    local axe = getTool({"axe","hatchet"})
    if not axe then print("[树] 无斧头"); debugTools(); return end
    eq(axe)
    local forest = WS:FindFirstChild("Forest")
    if not forest then print("[树] 无Forest"); return end
    local h = hrp(); if not h then return end
    local near = nil
    for _, c in ipairs(forest:GetChildren()) do
        if c:IsA("Model") then
            local t = c:FindFirstChild("Trunk")
            if t then local d = (t.Position-h.Position).Magnitude; if d<=S.Range+20 then near={M=c,P=t,D=d} end end
        end
    end
    if not near then print("[树] 无树"); return end
    print(string.format("[树] %s @%.1fm 前往...", near.M.Name, near.D))
    h.CFrame = near.P.CFrame * CFrame.new(0, 0, 4)
    wait(0.5)
    local ok, err = pcall(function() BNR:FireServer(mkTB(), {near.P}) end)
    if ok then
        print("[树] OK")
        if homePos then wait(0.5); local h2=hrp(); if h2 then h2.CFrame=CFrame.new(homePos) end end
    else
        print("[树] 失败:"..tostring(err))
    end
    wait(1)
end

-- ===== 拖动回家 =====
local function dragHome()
    if not S.Drag or not RD or not RL or not homePos then return end
    local h = hrp(); if not h then return end
    for _, obj in ipairs(CS:GetTagged("Draggable")) do
        local t = obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)))
        if t and (t.Position-h.Position).Magnitude <= S.Range then
            print("[拖] "..obj.Name.." @"..string.format("%.0f",(t.Position-h.Position).Magnitude).."m")
            h.CFrame = t.CFrame * CFrame.new(0,0,3); wait(0.4)
            local ok = pcall(function() RD:FireServer(obj) end)
            if ok then
                wait(0.3); h.CFrame = CFrame.new(homePos.X, homePos.Y+2, homePos.Z); wait(0.5)
                pcall(function() RL:FireServer() end)
                print("[拖] 到家")
            end
            break
        end
    end
    wait(0.5)
end

-- ===== 设置家点 =====
local function setHome()
    local h=hrp()
    if not h then if WI then WI:Notify({Title="错误",Content="找不到角色",Duration=2}) end; return end
    homePos=h.Position
    if WI then WI:Notify({Title="家点已设",Content="可拖动物品自动传回",Duration=3}) end
    print("[家] "..string.format("%.1f,%.1f,%.1f",homePos.X,homePos.Y,homePos.Z))
end

-- ===== 先弹 Popup =====
local PP=false
if WI then
    WI:Popup({Title="北极生存 v2.2", Content="走到挖掘点挖雪 | ByteNet砍树 | 拖动回家", Buttons={{Title="加载", Callback=function() PP=true end, Variant="Primary"},{Title="取消", Callback=function() return end}}})
end
while not PP do wait(0.1) end

-- ===== 点了加载才创建 UI =====
print("[北极] 创建窗口...")
if WI then
    WN = WI:CreateWindow({
        Title="北极生存 v2.2", Author="b站英吉利超入_", Icon="solar:snowflake-bold",
        Size=UDim2.fromOffset(750,520), ToggleKey=Enum.KeyCode.RightShift,
        Folder="arctic-script", Acrylic=true, Resizable=false,
        ScrollBarEnabled=true, HideSearchBar=true,
        OnClose=function() S.Snow=false; S.Wood=false; S.Drag=false end
    })
    spawn(function() wait(0.8) pcall(function() if WN and WN.Parent then WN.Parent.ClipsDescendants=true end end) end)

    local t1=WN:Tab({Title="主控", Icon="solar:slider-vertical-bold"})
    S.Snow = false; S.Wood = false; S.Drag = false
    CT.Snow = t1:Toggle({Flag="SN", Title="挖雪 (走到挖掘点+Auger)", Value=false, Callback=function(v) S.Snow=v; print("[开关] 挖雪="..tostring(v)) end})
    t1:Space()
    CT.Wood = t1:Toggle({Flag="WD", Title="砍树 (ByteNet+Axe)", Value=false, Callback=function(v) S.Wood=v; print("[开关] 砍树="..tostring(v)) end})
    t1:Space()
    CT.Drag = t1:Toggle({Flag="DR", Title="拖动回家 (RequestDrag)", Value=false, Callback=function(v) S.Drag=v; print("[开关] 拖动="..tostring(v)) end})
    t1:Divider()
    t1:Button({Title="设置家点", Icon="solar:home-bold", Justify="Center",
        Color=Color3.fromHex("#50C878"), Callback=setHome})
    t1:Space()
    CT.Range = t1:Slider({Flag="RG", Title="收集范围", Step=5,
        Value={Min=10, Max=150, Default=60}, Width=200, IsTextbox=true,
        Callback=function(v) S.Range=v end})

    local t2=WN:Tab({Title="快捷键", Icon="solar:settings-bold"})
    t2:Keybind({Flag="TK", Title="窗口开关", Value="RightShift", Callback=function(v) end})

    local t3=WN:Tab({Title="UI", Icon="solar:monitor-bold"})
    if WI.ToggleAcrylic then
        t3:Toggle({Flag="AC", Title="毛玻璃", Value=true, Callback=function(v) pcall(function() WI:ToggleAcrylic(v) end) end})
    end
    local tns={"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    if WI.SetTheme then
        t3:Dropdown({Flag="TH", Title="主题", Values=tns, Value="Dark", Callback=function(v) pcall(function() WI:SetTheme(v) end) end})
    end

    local t4=WN:Tab({Title="信息", Icon="solar:chart-bold"})

    local t5=WN:Tab({Title="关于", Icon="solar:info-square-bold"})
    t5:Paragraph({Title="北极生存 v2.2"}); t5:Divider()
    t5:Paragraph({Title="作者", Desc="b站英吉利超入_"})
    t5:Paragraph({Title="说明", Desc="挖雪:走到DigPoint+Auger+ByteNet | 砍树:Axe+ByteNet+{Trunk} | 拖动:RequestDrag回家"})
end

print("[北极] v2.2 开始运行")

spawn(function()
    while true do
        if S.Snow then pcall(digSnow) end; wait(0.3)
        if S.Wood then pcall(cutTree) end; wait(0.3)
        if S.Drag then pcall(dragHome) end; wait(0.3)
        wait(0.5)
    end
end)
