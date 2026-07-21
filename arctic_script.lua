--[[
    北极生存7天 - 自动收集物资 v2.0
    WindUI 三路加载 + ByteNet 挖雪/砍树 + 家点传送
    中文界面
--]]

print("[北极] v2.0 加载中...")

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local LP = P.LocalPlayer
if not LP then return end
print("[北极] 玩家: " .. LP.Name)

-- 清理
for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") and (g.Name == "A" or g.Name:find("Arctic") or g.Name == "WindUI") then
        pcall(function() g:Destroy() end)
    end
end

-- 三路加载 WindUI
print("[北极] 加载 WindUI...")
local WI = nil
local function tryLoadWindUI()
    -- 方式1: 本地读取 (readfile)
    local ok1, src1 = pcall(function() return readfile("windui_source.lua") end)
    if ok1 and src1 and #src1 > 100 then
        local ok, mod = pcall(loadstring, src1)
        if ok and mod then
            local ok2, inst = pcall(mod)
            if ok2 and inst then return inst end
        end
    end
    -- 方式2: 联网
    for i = 1, 3 do
        local ok, src2 = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua")
        end)
        if ok and src2 and #src2 > 100 then
            local ok, mod = pcall(loadstring, src2)
            if ok and mod then
                local ok2, inst = pcall(mod)
                if ok2 and inst then return inst end
            end
        end
        if i < 3 then wait(1) end
    end
    return nil
end
WI = tryLoadWindUI()
print("[北极] WindUI=" .. (WI and "OK" or "NIL"))

-- 远程事件
local Remotes = RS:FindFirstChild("Remotes")
local RequestDrag = Remotes and Remotes:FindFirstChild("RequestDrag")
local ReleaseDrag = Remotes and Remotes:FindFirstChild("ReleaseDrag")
local ByteNetReliable = RS:FindFirstChild("ByteNetReliable")
print("[北极] 事件: ReqDrag=" .. (RequestDrag and "OK" or "NIL") .. " RelDrag=" .. (ReleaseDrag and "OK" or "NIL") .. " ByteNet=" .. (ByteNetReliable and "OK" or "NIL"))

local bufferOK = pcall(function() return buffer.create end)
print("[北极] buffer=" .. (bufferOK and "OK" or "NIL"))

-- Cobalt buffer
local snowBytes = {39, 108, 84, 138, 63}
local function makeSnowBuffer()
    local b = buffer.create(#snowBytes)
    for i = 1, #snowBytes do buffer.writeu8(b, i-1, snowBytes[i]) end
    return b
end
local treeBytes = {41,3,0,65,120,101,8,0,65,120,101,83,119,105,110,103,20,1,42,197,127,191,99,221,42,61,220,52,242,59,69,171,14,68,253,170,165,66,172,8,26,68}
local function makeTreeBuffer()
    local b = buffer.create(#treeBytes)
    for i = 1, #treeBytes do buffer.writeu8(b, i-1, treeBytes[i]) end
    return b
end

local homePos, WN, CT, PR, PS, PC = nil, nil, {}, false, {}, nil
local S = {AutoCollect=false, CollectWood=true, CollectStone=true, CollectFood=false, CollectDrag=true, AutoSnow=false, Range=50, AugerRange=15, Particles=true, Acrylic=true, Transparent=false, ParticleColor=Color3.fromRGB(80,170,255)}
local KB = {Toggle="RightShift"}

local function getTool(kw)
    for _, src in ipairs({LP.Character, LP:FindFirstChild("Backpack")}) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") then
                    local ln = t.Name:lower()
                    for _, k in ipairs(kw) do if ln:find(k,1,true) then return t end end
                end
            end
        end
    end
    return nil
end
local function equip(t)
    if not t then return false end
    local c=LP.Character; if not c then return false end
    local h=c:FindFirstChildOfClass("Humanoid"); if not h then return false end
    if t.Parent~=c then h:EquipTool(t); wait(0.2) end
    return true
end
local function hrp() local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

-- 挖雪
local function digSnow()
    if not S.AutoSnow or not ByteNetReliable or not bufferOK then return end
    local auger=getTool({"auger","drill"}); if not auger then print("[挖雪] 无Auger"); return end
    equip(auger)
    local things=WS:FindFirstChild("Things"); local dp=things and things:FindFirstChild("DigPoint")
    local dh=things and things:FindFirstChild("DigHere"); local h=hrp(); if not h then return end
    local tp=dp and dp.Position or (dh and dh.Position)
    if not tp then print("[挖雪] 无挖掘点"); return end
    local d=(tp-h.Position).Magnitude
    if d>S.AugerRange then print(string.format("[挖雪] %.1fm>%dm",d,S.AugerRange)); return end
    print(string.format("[挖雪] %.1fm",d))
    h.CFrame=CFrame.lookAt(h.Position,tp); wait(0.2)
    local ok,err=pcall(function() ByteNetReliable:FireServer(makeSnowBuffer(),nil) end)
    print(ok and "[挖雪] OK" or ("[挖雪] 失败:"..tostring(err)))
    wait(0.5)
end

-- 砍树
local function cutTree()
    if not S.CollectWood or not ByteNetReliable or not bufferOK then return end
    local axe=getTool({"axe","hatchet"}); if not axe then print("[砍树] 无斧头"); return end
    equip(axe); local forest=WS:FindFirstChild("Forest")
    if not forest then print("[砍树] Forest不存在"); return end
    local h=hrp(); if not h then return end; local pos=h.Position; local near=nil
    for _,c in ipairs(forest:GetChildren()) do
        if c:IsA("Model") then
            local t=c:FindFirstChild("Trunk")
            if t then local d=(t.Position-pos).Magnitude; if d<=S.Range+10 and (not near or d<near.D) then near={M=c,P=t,D=d} end end
        end
    end
    if not near then print("[砍树] 无树"); return end
    print(string.format("[砍树] %s @%.1fm",near.M.Name,near.D))
    h.CFrame=near.P.CFrame*CFrame.new(0,0,4); wait(0.3)
    local ok,err=pcall(function() ByteNetReliable:FireServer(makeTreeBuffer(),{near.P}) end)
    if ok then print("[砍树] OK"); wait(0.8)
        if homePos then local h2=hrp(); if h2 then h2.CFrame=CFrame.new(homePos); wait(0.2) end end
    else print("[砍树] 失败:"..tostring(err)) end
end

-- 拖动
local function getDrag()
    local items={}; local h=hrp(); local pos=h and h.Position; if not pos then return items end
    for _,obj in ipairs(CS:GetTagged("Draggable")) do
        local t=obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)))
        if t then local d=(t.Position-pos).Magnitude; if d<=S.Range+10 then table.insert(items,{M=obj,P=t,D=d}) end end
    end
    table.sort(items,function(a,b) return a.D<b.D end); return items
end
local function dragHome(item)
    if not item or not RequestDrag or not ReleaseDrag then return end
    local h=hrp(); if not h then return end
    print("[拖动] "..item.M.Name.." @"..string.format("%.1f",item.D).."m")
    h.CFrame=item.P.CFrame*CFrame.new(0,0,3); wait(0.4)
    local ok1=pcall(function() RequestDrag:FireServer(item.M) end)
    if not ok1 then print("[拖动] RequestDrag失败"); return end
    print("[拖动] 已抓起"); wait(0.3)
    if homePos then h.CFrame=CFrame.new(homePos.X,homePos.Y+2,homePos.Z); wait(0.5) end
    pcall(function() ReleaseDrag:FireServer() end); print("[拖动] 已放下")
end
local function doDrag()
    if not S.CollectDrag or not RequestDrag or not ReleaseDrag then return end
    local items=getDrag(); if #items==0 then return end; dragHome(items[1])
end

-- 挖石头
local function mine()
    if not S.CollectStone or not ByteNetReliable or not bufferOK then return end
    local s=getTool({"shovel","pickaxe"}); if not s then return end; equip(s)
    local things=WS:FindFirstChild("Things"); local dp=things and things:FindFirstChild("DigPoint")
    local h=hrp(); if not h or not dp then return end
    local d=(dp.Position-h.Position).Magnitude; if d>S.AugerRange then return end
    h.CFrame=CFrame.lookAt(h.Position,dp.Position); wait(0.2)
    local ok,err=pcall(function() ByteNetReliable:FireServer(makeSnowBuffer(),nil) end)
    print(ok and "[挖矿] OK" or ("[挖矿] 失败:"..tostring(err)))
    if homePos then local h2=hrp(); if h2 then h2.CFrame=CFrame.new(homePos); wait(0.2) end end
end

-- 食物
local function getFood()
    local foods={}; local h=hrp(); local pos=h and h.Position; if not pos then return foods end
    for _,obj in ipairs(CS:GetTagged("Edible")) do
        local t=obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)))
        if t then local d=(t.Position-pos).Magnitude; if d<=S.Range+10 then table.insert(foods,{M=obj,P=t,D=d}) end end
    end
    table.sort(foods,function(a,b) return a.D<b.D end); return foods
end
local function doFood()
    if not S.CollectFood then return end; local fd=getFood(); if #fd==0 then return end
    local f=fd[1]; local h=hrp(); if not h then return end
    h.CFrame=f.P.CFrame*CFrame.new(0,0,2); wait(0.2)
    if RequestDrag then pcall(function() RequestDrag:FireServer(f.M) end); print("[食物] "..f.M.Name) end
    if homePos then local h2=hrp(); if h2 then h2.CFrame=CFrame.new(homePos); wait(0.2) end end
end

-- 粒子
local function sP()
    if PR then return end
    if PC then pcall(function() local p=PC.Parent; if p then p:Destroy() end end); PC=nil end; PS={}; wait(0.3)
    local sg=Instance.new("ScreenGui"); sg.Name="AP"; sg.ResetOnSpawn=false; sg.DisplayOrder=999999; sg.IgnoreGuiInset=true; sg.Parent=C
    PC=Instance.new("Frame"); PC.Size=UDim2.new(1,0,1,0); PC.BackgroundTransparency=1; PC.BorderSizePixel=0; PC.Parent=sg
    for i=1,50 do
        local d=Instance.new("Frame"); local sz=math.random(5,10)
        d.Size=UDim2.new(0,sz,0,sz); d.Position=UDim2.new(0.2+math.random()*0.6,0,0.2+math.random()*0.6,0)
        d.BackgroundColor3=S.ParticleColor; d.BackgroundTransparency=0.3+math.random()*0.5; d.BorderSizePixel=0; d.Parent=PC
        Instance.new("UICorner",d).CornerRadius=UDim.new(0,10)
        local a=math.random()*6.28; local sp=0.0008+math.random()*0.002
        table.insert(PS,{F=d,Sx=d.Position.X.Scale,Sy=d.Position.Y.Scale,Vx=math.cos(a)*sp,Vy=math.sin(a)*sp,Ph=math.random()*6.28,Sz=sz})
    end
    PR=true
    spawn(function() local t=0; while PR and PC do t=t+0.03
        pcall(function() local c=S.ParticleColor; for _,p in ipairs(PS) do if p.F and p.F.Parent then
            local sx=math.max(0.05,math.min(0.95,p.Sx+p.Vx)); local sy=math.max(0.05,math.min(0.95,p.Sy+p.Vy))
            if sx>=0.95 or sx<=0.05 then p.Vx=-p.Vx end; if sy>=0.95 or sy<=0.05 then p.Vy=-p.Vy end
            p.Sx=sx; p.Sy=sy; p.F.Position=UDim2.new(sx,0,sy,0); p.F.BackgroundColor3=c
            p.F.BackgroundTransparency=0.3+math.sin(t*0.8+p.Ph)*0.4
            p.F.Size=UDim2.new(0,math.max(2,p.Sz+math.sin(t+p.Ph)*1.5),0,math.max(2,p.Sz+math.sin(t+p.Ph)*1.5))
    end end end) wait(0.03) end end)
end
local function xP() PR=false; if PC then pcall(function() local p=PC.Parent; if p then p:Destroy() end end); PC=nil end; PS={} end

-- 主题
local tc_t={Dark=Color3.fromRGB(80,170,255),Light=Color3.fromRGB(60,130,210),Rose=Color3.fromRGB(255,130,170),Plant=Color3.fromRGB(70,210,130),Ocean=Color3.fromRGB(60,190,240),Sunset=Color3.fromRGB(255,160,70),Midnight=Color3.fromRGB(130,100,240),Forest=Color3.fromRGB(60,180,90),Lavender=Color3.fromRGB(190,140,255),Coral=Color3.fromRGB(255,140,90),Mint=Color3.fromRGB(80,230,190),Sky=Color3.fromRGB(100,190,255),Blood=Color3.fromRGB(230,90,80),Lemon=Color3.fromRGB(230,210,70),Cyber=Color3.fromRGB(0,235,210)}
local function tc(n) return tc_t[n] or Color3.fromRGB(80,170,255) end

-- 设置家点
local function setHome()
    local h=hrp()
    if not h then if WI then WI:Notify({Title="错误",Content="找不到角色位置",Duration=2}) end; return end
    homePos=h.Position
    if WI then WI:Notify({Title="家点已设置",Content="拿起物品后自动传送回家放下",Duration=3}) end
    print(string.format("[家点] %.1f,%.1f,%.1f",homePos.X,homePos.Y,homePos.Z))
end

-- UI
local function mW()
    if not WI then print("[北极] 无WindUI,跳过UI创建"); return end
    WN=WI:CreateWindow({Title="北极生存 v2.0",Author="b站英吉利超入_",Icon="solar:snowflake-bold",Size=UDim2.fromOffset(750,560),ToggleKey=Enum.KeyCode.RightShift,Folder="arctic-script",Acrylic=true,Resizable=false,ScrollBarEnabled=true,HideSearchBar=true,OnClose=function() xP();S.AutoCollect=false;S.AutoSnow=false;for _,ct in pairs(CT) do if ct and type(ct.Set)=="function" then pcall(function() ct:Set(false) end) end end end,OnOpen=function() if S.Particles then sP() end end})
    spawn(function() wait(0.8) pcall(function() if WN and WN.Parent then WN.Parent.ClipsDescendants=true end end) end)
    local t1=WN:Tab({Title="主控面板",Icon="solar:slider-vertical-bold"})
    CT.AutoCollect=t1:Toggle({Flag="AC",Title="自动收集",Value=false,Callback=function(v) S.AutoCollect=v end})
    t1:Divider()
    CT.AutoSnow=t1:Toggle({Flag="AS",Title="挖雪(Auger)",Value=false,Callback=function(v) S.AutoSnow=v end})
    t1:Space()
    CT.CollectWood=t1:Toggle({Flag="CW",Title="木头(ByteNet砍树)",Value=true,Callback=function(v) S.CollectWood=v end})
    CT.CollectStone=t1:Toggle({Flag="CS",Title="石头(Shovel)",Value=true,Callback=function(v) S.CollectStone=v end})
    CT.CollectFood=t1:Toggle({Flag="CF",Title="食物(浆果)",Value=false,Callback=function(v) S.CollectFood=v end})
    CT.CollectDrag=t1:Toggle({Flag="CD",Title="拖动回家",Value=true,Callback=function(v) S.CollectDrag=v end})
    t1:Divider()
    t1:Button({Title="设置家点",Icon="solar:home-bold",Justify="Center",Color=Color3.fromHex("#50C878"),Callback=setHome})
    t1:Space()
    CT.Range=t1:Slider({Flag="RG",Title="收集范围",Step=5,Value={Min=10,Max=150,Default=50},Width=200,IsTextbox=true,Callback=function(v) S.Range=v end})
    local t2=WN:Tab({Title="快捷键",Icon="solar:settings-bold"})
    t2:Keybind({Flag="TK",Title="窗口开关",Value="RightShift",Callback=function(v) end})
    local t3=WN:Tab({Title="UI设置",Icon="solar:monitor-bold"})
    CT.Particles=t3:Toggle({Flag="PT",Title="粒子背景",Value=true,Callback=function(v) S.Particles=v;if v then sP()else xP()end end})
    t3:Toggle({Flag="ACR",Title="毛玻璃",Value=true,Callback=function(v) pcall(function() WI:ToggleAcrylic(v) end) end})
    t3:Toggle({Flag="TR",Title="透明",Value=false,Callback=function(v) pcall(function() WN:ToggleTransparency(v) end) end})
    local tns={"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    t3:Dropdown({Flag="TH",Title="主题",Values=tns,Value="Dark",Callback=function(v) pcall(function() WI:SetTheme(v) end);S.ParticleColor=tc(v) end})
    local t4=WN:Tab({Title="信息统计",Icon="solar:chart-bold"})
    local sWood=t4:Paragraph({Title="树木:0"}); local sStone=t4:Paragraph({Title="石头:0"})
    local sFood=t4:Paragraph({Title="食物:0"}); local sDragP=t4:Paragraph({Title="可拖动:0"})
    local t5=WN:Tab({Title="配置管理",Icon="solar:diskette-bold"})
    pcall(function()
        local CM=WN.ConfigManager; if not CM then return end
        local cni=t5:Input({Flag="CN",Title="配置名称",Value="default",Icon="solar:file-text-bold",Callback=function(v) end})
        t5:Space(); local AC={}; pcall(function() AC=CM:AllConfigs() end)
        local DV=nil; for _,v in ipairs(AC) do if v=="default" then DV="default";break end end
        local ACD=t5:Dropdown({Title="已有配置",Values=AC,Value=DV,Callback=function(v) if v then pcall(function() cni:Set(v) end) end end})
        t5:Space(); t5:Button({Title="保存",Icon="solar:check-circle-bold",Justify="Center",Color=Color3.fromHex("#305dff"),Callback=function() if not CM then return end;local c=CM:Config("default");if c and c:Save() then WI:Notify({Title="已保存",Content="OK",Duration=3}) end end})
        t5:Space(); t5:Button({Title="加载",Icon="solar:refresh-circle-bold",Justify="Center",Color=Color3.fromHex("#10C550"),Callback=function() if not CM then return end;local c=CM:CreateConfig("default",false);if c and c:Load() then WI:Notify({Title="已加载",Content="OK",Duration=3}) end end})
        t5:Space(); t5:Button({Title="删除",Icon="solar:trash-bin-trash-bold",Justify="Center",Color=Color3.fromHex("#ff3040"),Callback=function() if not CM then return end;local c=CM:Config("default");if c and c:Delete() then WI:Notify({Title="已删除",Content="OK",Duration=3}) end end})
        spawn(function() wait(1) pcall(function() CM:CreateConfig("default",true) end) end)
    end)
    local t6=WN:Tab({Title="关于",Icon="solar:info-square-bold"})
    t6:Paragraph({Title="北极生存 v2.0"}); t6:Divider()
    t6:Paragraph({Title="作者",Desc="b站英吉利超入_"})
    t6:Paragraph({Title="说明",Desc="Auger挖雪+ByteNet砍树+拖动回家+家点传送"})
    return sWood,sStone,sFood,sDragP
end

-- 启动
pcall(function() WI:SetTheme("Dark") end)
S.ParticleColor=tc("Dark")

if WI then
    local PP=false
    WI:Popup({Title="北极生存 v2.0",Content="三路WindUI加载 | ByteNet挖雪/砍树 | 家点传送",Buttons={{Title="加载",Callback=function() PP=true end,Variant="Primary"},{Title="取消",Callback=function() return end}}})
    while not PP do wait(0.1) end
end

spawn(function()
    local sWood,sStone,sFood,sDrag=mW()
    print("[北极] v2.0 开始运行")
    local start=os.clock()
    while true do
        if S.AutoSnow then pcall(digSnow) end; wait(0.3)
        if S.AutoCollect then
            if S.CollectWood then pcall(cutTree) end; wait(0.5)
            if S.CollectStone then pcall(mine) end; wait(0.3)
            if S.CollectFood then pcall(doFood) end; wait(0.3)
            if S.CollectDrag then pcall(doDrag) end; wait(0.3)
        end
        wait(0.3)
        if os.clock()-start>3 then
            start=os.clock()
            if sWood then local f=WS:FindFirstChild("Forest");pcall(function() sWood:SetTitle("树木:"..(f and #f:GetChildren() or 0)) end) end
            if sDrag then pcall(function() sDrag:SetTitle("可拖动:"..#CS:GetTagged("Draggable")) end) end
            if sFood then pcall(function() sFood:SetTitle("食物:"..#CS:GetTagged("Edible")) end) end
        end
    end
end)
