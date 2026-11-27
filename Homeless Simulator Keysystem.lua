-- Homeless Simulator | Auto Minigames (Semir + Ngamen) dengan WindUI
-- Toggle ON/OFF lewat UI WindUI (tab "Minigames")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

-- Load WindUI kalau belum ada di environment
local WindUI = WindUI
if not WindUI then
    WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end

-- Hentikan instance lama kalau script dijalankan ulang
if getgenv then
    local g = getgenv()
    if g.__HS_AutoMinigames_Stop then pcall(g.__HS_AutoMinigames_Stop) end
end

local alive = true
local connections = {}
local function track(c) table.insert(connections, c) return c end

-- ====================================================================
-- STATE
-- ====================================================================
local semirOn = false
local ngamenOn = false
local farmOn = false
local avoidOn = true      -- hindari pemain lain saat farm
local avoidRadius = 50    -- studs (diatur lewat slider 10-100)

local antiAfkOn = true -- Anti AFK (anti idle + anti kick), default ON

local setFarm -- diisi oleh modul Auto Farm Rongsok
local setAntiAfk -- diisi oleh modul Anti AFK

-- ====================================================================
-- AUTO SEMIR (keyboard)
-- ====================================================================
local KEY_KIRI  = Enum.KeyCode.A
local KEY_KANAN = Enum.KeyCode.D
local KEY_SPASI = Enum.KeyCode.Space

local TAP_DELAY   = 0.01
local TAP_HOLD    = 0.02
local BAR_FULL    = 264
local FULL_TOL    = 3
local NEEDLE_INVERT = false

local LEAD_TIME = 0.12
local MIN_TAP_INTERVAL = 0.04
local VEL_SMOOTH = 0.75
local AXIS = "auto"
local START_GRACE = 0.3
local STABLE_MAX  = 0.3

local function keyEvent(state, key)
    VIM:SendKeyEvent(state, key, false, game)
end

local function releaseSemirKeys()
    keyEvent(false, KEY_SPASI)
    keyEvent(false, KEY_KIRI)
    keyEvent(false, KEY_KANAN)
end

local function tapKey(key)
    keyEvent(true, key)
    task.wait(TAP_HOLD)
    keyEvent(false, key)
end

-- Tap spasi tanpa tumpang tindih
local spaceBusy = false
local function tapSpace()
    if spaceBusy then return end
    spaceBusy = true
    task.spawn(function()
        tapKey(KEY_SPASI)
        spaceBusy = false
    end)
end

local function getPanel()
    local sg = PG:FindFirstChild("SemirGui")
    local w = sg and sg:FindFirstChild("Wadah")
    return w and w:FindFirstChild("PanelGosok")
end

-- Cek objek benar-benar tampil (termasuk ScreenGui.Enabled)
local function shown(obj)
    if not obj then return false end
    local cur = obj
    while cur do
        if cur:IsA("GuiObject") then
            if not cur.Visible then return false end
        elseif cur:IsA("ScreenGui") then
            return cur.Enabled
        elseif not cur:IsA("GuiBase2d") then
            break
        end
        cur = cur.Parent
    end
    return true
end

local function barFull(bar)
    return bar.Size.X.Offset >= (BAR_FULL - FULL_TOL)
end

local function waitStable(obj, maxT)
    local t0 = os.clock()
    local lastPos, lastSize = obj.AbsolutePosition, obj.AbsoluteSize
    local stableFrames = 0
    while os.clock() - t0 < maxT and stableFrames < 3 do
        RunService.Heartbeat:Wait()
        local p, s = obj.AbsolutePosition, obj.AbsoluteSize
        if p == lastPos and s == lastSize then
            stableFrames += 1
        else
            stableFrames = 0
            lastPos, lastSize = p, s
        end
    end
end

local function semirActive()
    return alive and semirOn
end

-- Minigame 1: A & D bergantian
local function mini1(panel, bar)
    local kiri = panel:FindFirstChild("TombolKiriN")
    local side = false
    while semirActive() and shown(kiri) and not barFull(bar) do
        tapKey(side and KEY_KANAN or KEY_KIRI)
        side = not side
        task.wait(TAP_DELAY)
    end
end

-- Minigame 2: tahan Spasi sampai bar kena zona hijau
local function mini2(panel, bar, zone)
    local tahan = panel:FindFirstChild("TombolTahanN")
    keyEvent(true, KEY_SPASI)
    while semirActive() and shown(tahan) do
        local barRight = bar.AbsolutePosition.X + bar.AbsoluteSize.X
        if barRight >= zone.AbsolutePosition.X then break end
        RunService.Heartbeat:Wait()
    end
    keyEvent(false, KEY_SPASI)

    local t = os.clock()
    while semirActive() and shown(tahan) and os.clock() - t < 0.5 do
        RunService.Heartbeat:Wait()
    end
end

-- Minigame 3: tap Spasi, jarum jaga di tengah zona hijau
local function mini3(panel, bar, zone, jarum)
    local gosok = panel:FindFirstChild("TombolGosokN")
    local track_ = zone.Parent

    waitStable(zone, STABLE_MAX)

    local axis = AXIS
    if axis == "auto" then
        axis = (track_.AbsoluteSize.X >= track_.AbsoluteSize.Y) and "x" or "y"
    end
    local sign = NEEDLE_INVERT and -1 or 1

    local function coord(o)
        if axis == "x" then
            return sign * (o.AbsolutePosition.X + o.AbsoluteSize.X / 2)
        else
            return sign * -(o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2)
        end
    end

    local prev = coord(jarum)
    local prevT = os.clock()
    local vel = 0
    local lastTap = 0
    local startT = os.clock()

    while semirActive() and shown(gosok)
        and (not barFull(bar) or os.clock() - startT < START_GRACE) do
        RunService.Heartbeat:Wait()

        local now = os.clock()
        local dt = now - prevT
        local cur = coord(jarum)
        if dt > 0 then
            local raw = (cur - prev) / dt
            vel = vel * (1 - VEL_SMOOTH) + raw * VEL_SMOOTH
            prev = cur
            prevT = now
        end

        local predicted = cur + vel * LEAD_TIME
        local target = coord(zone)

        if predicted < target and (now - lastTap) >= MIN_TAP_INTERVAL then
            lastTap = now
            tapSpace()
        end
    end
end

-- Loop utama Semir
task.spawn(function()
    while alive do
        RunService.Heartbeat:Wait()
        if not semirOn then continue end

        local ok, err = pcall(function()
            local panel = getPanel()
            if not panel or not shown(panel) then return end

            local img = panel:FindFirstChild("ImageLabel")
            local bar = img and img:FindFirstChild("Frame")
            local zone = img and img:FindFirstChild("ZonaHijau")
            local jarum = img and img:FindFirstChild("Jarum")
            if not bar then return end

            local kiri = panel:FindFirstChild("TombolKiriN")
            local tahan = panel:FindFirstChild("TombolTahanN")
            local gosok = panel:FindFirstChild("TombolGosokN")

            if shown(kiri) then
                mini1(panel, bar)
            elseif shown(tahan) and zone then
                mini2(panel, bar, zone)
            elseif shown(gosok) and zone and jarum then
                mini3(panel, bar, zone, jarum)
            end
        end)
        if not ok then
            releaseSemirKeys()
            warn("[AutoSemir] error: " .. tostring(err))
            task.wait(0.2)
        end
    end
end)

local function setSemir(v)
    semirOn = v
    if not v then
        spaceBusy = false
        releaseSemirKeys()
    end
end

-- ====================================================================
-- AUTO NGAMEN (Z/X + mouse)
-- Game menghitung posisi ketukan = GetMouseLocation() - GetGuiInset(),
-- jadi kursor harus di AbsolutePosition + GetGuiInset().
-- ====================================================================
local KEY_1 = Enum.KeyCode.Z
local KEY_2 = Enum.KeyCode.X

local PRE_AIM_LEAD = 0.22
local LEAD = 0.015
local HIT_AT = 1.0
local SKIP_RATIO = 0.55
local TAP_HOLD_N = 0.09
local JITTER = 0
local OFFSET_X = 0
local OFFSET_Y = 0
local BOLA_START_TIMEOUT = 0.35
local MAX_HOLD = 4
local BUSY_WAIT = 0.15
local SHOW_DOT = false
local DEBUG = false

local busy = false
local aimOwner = nil
local useSecondKey = true
local jitState = false
local calX, calY = 0, 0
local calibrated = false

local function nextKey()
    useSecondKey = not useSecondKey
    return useSecondKey and KEY_2 or KEY_1
end

local function log(...)
    if DEBUG then print("[AutoNgamen]", ...) end
end

-- ScreenGui hanya dibuat kalau titik debug dipakai
local dotUi
local function showDot(x, y)
    if not SHOW_DOT then return end
    if not dotUi or not dotUi.Parent then
        dotUi = Instance.new("ScreenGui")
        dotUi.Name = "AutoNgamenDot"
        dotUi.ResetOnSpawn = false
        dotUi.IgnoreGuiInset = true
        dotUi.DisplayOrder = 999
        dotUi.Parent = (gethui and gethui()) or PG
    end
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(8, 8)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromOffset(x, y)
    dot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    dot.BorderSizePixel = 0
    dot.Active = false
    dot.Parent = dotUi
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    task.delay(0.15, function() if dot then dot:Destroy() end end)
end

local function targetPos(o)
    local p = o.AbsolutePosition + o.AbsoluteSize / 2 + GuiService:GetGuiInset()
    return p.X + OFFSET_X, p.Y + OFFSET_Y
end

local function moveMouseTo(x, y)
    VIM:SendMouseMoveEvent(x + calX, y + calY, game)
end

local function calibrate()
    local tx, ty = 300, 300
    for _ = 1, 2 do
        VIM:SendMouseMoveEvent(tx + calX, ty + calY, game)
        RunService.RenderStepped:Wait()
        RunService.RenderStepped:Wait()
        local actual = UIS:GetMouseLocation()
        local errX, errY = actual.X - tx, actual.Y - ty
        if math.abs(errX) > 1 or math.abs(errY) > 1 then
            calX -= errX
            calY -= errY
        end
    end
    calibrated = true
    log(string.format("Kalibrasi kursor: offset=(%.0f, %.0f)", calX, calY))
end

local function wiggleTo(x, y)
    if JITTER > 0 then
        jitState = not jitState
        moveMouseTo(x + (jitState and JITTER or -JITTER), y)
    else
        moveMouseTo(x, y)
    end
end

local function ensureCursorAt(x, y)
    local before = UIS:GetMouseLocation()
    moveMouseTo(x, y)
    if (Vector2.new(x, y) - before).Magnitude > 3 then
        RunService.RenderStepped:Wait()
        local after = UIS:GetMouseLocation()
        if (Vector2.new(x, y) - after).Magnitude > 3 then
            moveMouseTo(x, y)
            RunService.RenderStepped:Wait()
        end
    end
end

local function keyDown(x, y, key)
    showDot(x, y)
    ensureCursorAt(x, y)
    VIM:SendKeyEvent(true, key, false, game)
end

local function keyUp(key)
    VIM:SendKeyEvent(false, key, false, game)
end

local function ngamenActive()
    return alive and ngamenOn
end

local function setNgamen(v)
    ngamenOn = v
    if v then
        if not calibrated then task.spawn(calibrate) end
    else
        busy = false
        aimOwner = nil
        keyUp(KEY_1)
        keyUp(KEY_2)
    end
end

local function findRing(note)
    local direct = note:FindFirstChild("CincinPendekat")
    if direct then return direct end
    for _, d in ipairs(note:GetDescendants()) do
        if d.Name == "CincinPendekat" then return d end
    end
end

local function process(note)
    local name = note.Name
    local ring
    local t0 = os.clock()
    while note.Parent and not ring and os.clock() - t0 < 1 do
        ring = findRing(note)
        if not ring then task.wait(0.02) end
    end
    if not ring then log(name, "DILEWATI: cincin tidak ditemukan") return end

    local head = ring.Parent
    local bola = note:FindFirstChild("Bola")

    local prevR, prevT, vel = nil, nil, 0
    local ready, ratioAtHit, lastR = false, 0, 0
    while ngamenActive() and note.Parent and ring.Parent do
        local hw = head.AbsoluteSize.X
        if hw > 0 then
            local now = os.clock()
            local r = ring.AbsoluteSize.X / hw
            lastR = r
            if prevR then
                local dt = now - prevT
                if dt > 0 then vel = vel * 0.5 + ((r - prevR) / dt) * 0.5 end
            end
            prevR, prevT = r, now

            if not busy then
                local prePred = r + math.min(vel, 0) * PRE_AIM_LEAD
                if prePred <= HIT_AT and (aimOwner == nil or aimOwner == note) then
                    aimOwner = note
                    local hx, hy = targetPos(head)
                    wiggleTo(hx, hy)
                end
            end

            local predicted = r + math.min(vel, 0) * LEAD
            if predicted <= HIT_AT or r <= HIT_AT then
                if r < SKIP_RATIO then
                    if aimOwner == note then aimOwner = nil end
                    log(name, string.format("DILEWATI: terlambat r=%.2f", r))
                    return
                end
                ready, ratioAtHit = true, r
                break
            end
        end
        RunService.RenderStepped:Wait()
    end

    if not ready then
        if aimOwner == note then aimOwner = nil end
        log(name, string.format("DILEWATI: note hilang sebelum waktu tekan (r terakhir=%.2f)", lastR))
        return
    end

    local w = os.clock()
    while busy and os.clock() - w < BUSY_WAIT do RunService.RenderStepped:Wait() end
    if busy then
        if aimOwner == note then aimOwner = nil end
        log(name, "DILEWATI: kursor masih sibuk")
        return
    end
    if not note.Parent or not ngamenActive() then
        if aimOwner == note then aimOwner = nil end
        return
    end
    busy = true
    aimOwner = note

    local activeKey = nextKey()
    local x, y = targetPos(head)

    -- NOT TAP BIASA
    if not bola then
        keyDown(x, y, activeKey)
        local th = os.clock()
        repeat
            local hx, hy = targetPos(head)
            wiggleTo(hx, hy)
            RunService.RenderStepped:Wait()
        until os.clock() - th >= TAP_HOLD_N or not ngamenActive()
        keyUp(activeKey)

        log(name, string.format("OK [%s] ratio=%.2f akhir=tap", activeKey.Name, ratioAtHit))
        if aimOwner == note then aimOwner = nil end
        busy = false
        return
    end

    -- SLIDER
    keyDown(x, y, activeKey)
    local t1 = os.clock()
    local started = false
    local reason = "timeout"

    while ngamenActive() and (os.clock() - t1) < MAX_HOLD do
        if not note.Parent then reason = "slider selesai" break end
        if bola.Parent and bola.Visible then
            started = true
            local lx, ly = targetPos(bola)
            moveMouseTo(lx, ly)
        elseif started then
            reason = "bola selesai"
            break
        elseif os.clock() - t1 > BOLA_START_TIMEOUT then
            reason = "bola tidak muncul"
            break
        end
        RunService.RenderStepped:Wait()
    end

    keyUp(activeKey)
    if aimOwner == note then aimOwner = nil end
    busy = false
    log(name, string.format("OK [%s] ratio=%.2f tahan=%.2fs akhir=%s", activeKey.Name, ratioAtHit, os.clock() - t1, reason))
end

local function onNote(o)
    if not ngamenActive() or not o:IsA("GuiObject") then return end
    task.spawn(function()
        local ok, err = pcall(process, o)
        if not ok then
            busy = false
            if aimOwner == o then aimOwner = nil end
            keyUp(KEY_1)
            keyUp(KEY_2)
            warn("[AutoNgamen] error: " .. tostring(err))
        end
    end)
end

-- Watcher: GUI ngamen tidak selalu ada, jadi tunggu tanpa memblokir script
task.spawn(function()
    local lastFolder, conn
    while alive do
        local g = PG:FindFirstChild("NgamenOsuGui")
        local main = g and g:FindFirstChild("Main")
        local bidang = main and main:FindFirstChild("Bidang")
        local folder = bidang and bidang:FindFirstChild("Not")
        if folder and folder ~= lastFolder then
            if conn then conn:Disconnect() end
            lastFolder = folder
            conn = folder.ChildAdded:Connect(onNote)
        elseif not folder and lastFolder then
            if conn then conn:Disconnect() conn = nil end
            lastFolder = nil
        end
        task.wait(0.5)
    end
    if conn then conn:Disconnect() end
end)

-- ====================================================================
-- AUTO FARM RONGSOK (hindari pemain lain)
-- ====================================================================
do
    local function farmActive()
        return alive and farmOn
    end

    -- Lookup malas (lazy) supaya script tidak menggantung kalau objek belum ada
    local function getFolderRongsok()
        return workspace:FindFirstChild("Rongsok")
    end

    local function getPenjualPul()
        local m = workspace:FindFirstChild("Markas_Daerah1")
        local i = m and m:FindFirstChild("Isi")
        local l = i and i:FindFirstChild("LapakPul")
        return l and l:FindFirstChild("Penjual_Pul")
    end

    local function getLabelKarung()
        local hud = PG:FindFirstChild("UangHud")
        local f = hud and hud:FindFirstChild("Frame")
        local chip = f and f:FindFirstChild("ChipKarung")
        return chip and chip:FindFirstChild("TextLabel")
    end

    local function adaPlayerDekat(posisi, radius)
        if not avoidOn then return false end
        radius = radius or avoidRadius

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                local c = p.Character
                local h = c and c:FindFirstChild("HumanoidRootPart")
                local hm = c and c:FindFirstChildOfClass("Humanoid")
                if h and hm and hm.Health > 0 then
                    if (h.Position - posisi).Magnitude <= radius then
                        return true
                    end
                end
            end
        end
        return false
    end

    local function resetToastKarungPenuh()
        local toast = PG:FindFirstChild("RongsokToast")
        if not toast then return end
        for _, d in ipairs(toast:GetDescendants()) do
            if d:IsA("TextLabel") and string.find(string.upper(d.Text), "KARUNG PENUH") then
                d.Visible = false
                d.Text = ""
            end
        end
    end

    local function cekStatusKarung()
        local label = getLabelKarung()
        if not label then return nil, nil end
        local curStr, maxStr = string.match(tostring(label.Text), "(%d+)%s*/%s*(%d+)")
        return tonumber(curStr), tonumber(maxStr)
    end

    local function isKarungPenuh()
        local cur, maxCap = cekStatusKarung()
        if cur and maxCap and maxCap > 0 then
            return cur >= maxCap
        end
        return false
    end

    local function isTokoUIOpen()
        local tokoUI = PG:FindFirstChild("TokoUI")
        if not tokoUI then return false end
        if tokoUI:IsA("ScreenGui") and not tokoUI.Enabled then
            return false
        end
        local img = tokoUI:FindFirstChild("ImageLabel")
        return img and img:IsA("GuiObject") and img.Visible or false
    end

    local function tutupTokoUI()
        local tokoUI = PG:FindFirstChild("TokoUI")
        if not tokoUI then return end
        local img = tokoUI:FindFirstChild("ImageLabel")
        local closeBtn = img and img:FindFirstChild("ImageButton")
        if closeBtn and closeBtn:IsA("GuiButton") and closeBtn.Visible and closeBtn.Active then
            pcall(function()
                if firesignal then
                    firesignal(closeBtn.MouseButton1Click)
                    firesignal(closeBtn.Activated)
                end
                if closeBtn.Activate then
                    closeBtn:Activate()
                end
            end)
        end
    end

    local function getTargetPart(obj)
        if not obj then return nil end
        if obj:IsA("BasePart") then
            return obj
        elseif obj:IsA("Attachment") then
            return obj.Parent and obj.Parent:IsA("BasePart") and obj.Parent or nil
        elseif obj:IsA("Model") then
            return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end

    local function triggerPrompt(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return false end
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        local ok = pcall(function()
            if fireproximityprompt then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(0.08)
                prompt:InputHoldEnd()
            end
        end)
        return ok
    end

    local function klikTombol(btn)
        if not btn or not btn:IsA("GuiButton") then return false end
        if not btn.Visible or not btn.Active then return false end
        if btn.AbsoluteSize.X <= 0 or btn.AbsoluteSize.Y <= 0 then return false end

        local fired = false
        pcall(function()
            if firesignal then
                firesignal(btn.MouseButton1Down)
                firesignal(btn.MouseButton1Click)
                firesignal(btn.Activated)
                fired = true
            end
        end)

        pcall(function()
            if btn.Activate then
                btn:Activate()
                fired = true
            end
        end)

        if not fired then
            pcall(function()
                local cx = btn.AbsolutePosition.X + (btn.AbsoluteSize.X * 0.5)
                local cy = btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y * 0.5)
                VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
                task.wait(0.08)
                VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
                fired = true
            end)
        end

        return fired
    end

    local function temukanTombolSetor()
        local tokoUI = PG:FindFirstChild("TokoUI")
        if not tokoUI then return nil end

        local img = tokoUI:FindFirstChild("ImageLabel")
        local fr = img and img:FindFirstChild("Frame")
        local img2 = fr and fr:FindFirstChild("ImageLabel")
        local labelSetor = img2 and img2:FindFirstChild("TextLabel")

        if labelSetor and labelSetor:IsA("TextLabel") and labelSetor.Visible then
            local curr = labelSetor.Parent
            for _ = 1, 4 do
                if not curr then break end
                if curr:IsA("GuiButton") then
                    return curr
                end
                local btnInside = curr:FindFirstChildWhichIsA("GuiButton", true)
                if btnInside then
                    return btnInside
                end
                curr = curr.Parent
            end
        end

        for _, d in ipairs(tokoUI:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local lbl = d:FindFirstChildWhichIsA("TextLabel", true)
                if lbl and string.find(string.lower(lbl.Text), "setor") then
                    return d
                end
            end
        end

        return nil
    end

    local function klikSetorRongsok()
        local btn = temukanTombolSetor()
        if not btn then return false end
        return klikTombol(btn)
    end

    local function teleportJualKePul(hrp)
        local penjualPul = getPenjualPul()
        if not penjualPul then
            warn("[AutoFarm] Penjual_Pul tidak ditemukan!")
            return
        end
        local hrpPul = penjualPul:FindFirstChild("HumanoidRootPart") or getTargetPart(penjualPul)
        if not hrpPul or not hrp or not hrp.Parent then
            warn("[AutoFarm] HumanoidRootPart Penjual_Pul atau karakter tidak valid!")
            return
        end

        for _ = 1, 3 do
            if not farmActive() then break end

            local curBefore = cekStatusKarung()
            if curBefore ~= nil and curBefore <= 0 then
                break
            end

            -- tunggu sampai area penjual aman dari pemain lain
            local t0 = tick()
            while farmActive()
                and adaPlayerDekat(hrpPul.Position, avoidRadius)
                and (tick() - t0) < 10 do
                task.wait(0.5)
            end
            if not farmActive() or not hrp.Parent then break end

            hrp.CFrame = hrpPul.CFrame + (hrpPul.CFrame.LookVector * 3) + Vector3.new(0, 1.5, 0)
            task.wait(0.45)

            local promptPul = hrpPul:FindFirstChildWhichIsA("ProximityPrompt")
                or penjualPul:FindFirstChildWhichIsA("ProximityPrompt", true)
            if promptPul then
                triggerPrompt(promptPul)
            end

            local terbuka = false
            for _ = 1, 10 do
                if isTokoUIOpen() then
                    terbuka = true
                    break
                end
                task.wait(0.25)
            end

            if terbuka then
                task.wait(0.45)
                for _ = 1, 5 do
                    if not farmActive() then break end
                    local curCheck = cekStatusKarung()
                    if curCheck ~= nil and curCheck <= 0 then
                        break
                    end

                    klikSetorRongsok()
                    task.wait(0.55)

                    local curAfter = cekStatusKarung()
                    if curAfter ~= nil and curAfter <= 0 then
                        break
                    end
                end
                task.wait(0.4)
                tutupTokoUI()
                task.wait(0.4)
            end

            local curFinal = cekStatusKarung()
            if curFinal ~= nil and curFinal <= 0 then
                break
            end
            task.wait(0.35)
        end

        resetToastKarungPenuh()
    end

    setFarm = function(v)
        farmOn = v
        if v then resetToastKarungPenuh() end
    end

    task.spawn(function()
        while alive do
            if farmOn then
                local ok, err = pcall(function()
                    local char = LP.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local folderRongsok = getFolderRongsok()

                    if not (hrp and hum and hum.Health > 0 and folderRongsok) then return end

                    if isKarungPenuh() then
                        teleportJualKePul(hrp)
                    end

                    for _, desc in ipairs(folderRongsok:GetDescendants()) do
                        if not farmActive() then break end
                        if not hrp.Parent or hum.Health <= 0 then break end
                        if isKarungPenuh() then break end

                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            local partRongsok = getTargetPart(desc.Parent)
                            if partRongsok and partRongsok:IsA("BasePart")
                                and not adaPlayerDekat(partRongsok.Position) then
                                hrp.CFrame = partRongsok.CFrame + Vector3.new(0, 3, 0)
                                task.wait(0.12)
                                triggerPrompt(desc)
                                task.wait(0.12)

                                if isKarungPenuh() then
                                    teleportJualKePul(hrp)
                                    break
                                end
                            end
                        end
                    end
                end)
                if not ok then warn("[AutoFarm] error: " .. tostring(err)) end
            end
            task.wait(0.25)
        end
    end)
end

-- ====================================================================
-- ANTI AFK (anti idle + anti kick)
-- ====================================================================
do
    local VirtualUser = game:GetService("VirtualUser")
    local kickHookInstalled = false

    -- Anti idle: cegah kick AFK 20 menit bawaan Roblox
    track(LP.Idled:Connect(function()
        if not (alive and antiAfkOn) then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end))

    -- Anti kick: blokir pemanggilan LocalPlayer:Kick() dari script game (sisi klien).
    -- Tidak bisa menahan kick dari server atau moderasi Roblox.
    local function installKickHook()
        if kickHookInstalled then return end
        if not (hookmetamethod and getnamecallmethod) then
            warn("[AntiAFK] Executor tidak mendukung hookmetamethod; anti kick dilewati (anti idle tetap aktif).")
            return
        end

        local oldNamecall
        local function handler(self, ...)
            if antiAfkOn and alive and self == LP then
                local m = getnamecallmethod()
                if type(m) == "string" and m:lower() == "kick"
                    and not (checkcaller and checkcaller()) then
                    return nil
                end
            end
            return oldNamecall(self, ...)
        end

        local ok, err = pcall(function()
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure and newcclosure(handler) or handler)
        end)
        if ok then
            kickHookInstalled = true
        else
            warn("[AntiAFK] Gagal memasang hook anti kick: " .. tostring(err))
        end
    end

    setAntiAfk = function(v)
        antiAfkOn = v
        if v then installKickHook() end
    end

    setAntiAfk(antiAfkOn) -- default ON
end

-- ====================================================================
-- UI (WindUI)
-- ====================================================================
-- ====================================================================
-- KEY SYSTEM (work.ink)
-- ====================================================================
local HttpService = game:GetService("HttpService")

local WORKINK_LINK = "https://work.ink/2hAT/bae710b4-b121-42a3-9626-4a4974ee1546" -- link key system work.ink
local DELETE_TOKEN = false -- true = key hanya bisa dipakai 1x (SaveKey sebaiknya dimatikan)

local function validateWorkInk(key)
    if type(key) ~= "string" then return false end
    key = (key:gsub("%s+", ""))

    -- Token work.ink berupa UUID v4 (36 karakter); tolak yang lain sebelum request
    if #key ~= 36 or not key:match("^[%x%-]+$") then return false end

    local url = "https://work.ink/_api/v2/token/isValid/" .. key
        .. (DELETE_TOKEN and "?deleteToken=1" or "")

    local okGet, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not okGet then
        warn("[KeySystem] Gagal menghubungi work.ink: " .. tostring(body))
        return false
    end

    local okJson, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    return okJson and type(data) == "table" and data.valid == true
end

local Window = WindUI:CreateWindow({
    Title = "Homeless Simulator",
    Icon = "house",
    Author = "Guten",
    Folder = "HomelessSimHub", -- tempat key tersimpan

    KeySystem = {
        Title = "Key System",
        Note = "Klik <b>Get Key</b> untuk menyalin link, buka di browser, selesaikan langkahnya, lalu tempel key di sini.",
        URL = WORKINK_LINK,          -- disalin ke clipboard saat klik "Get Key"
        KeyValidator = validateWorkInk,
        SaveKey = not DELETE_TOKEN,  -- key tersimpan, tidak perlu input ulang selama masih valid
    },
})

local Tab = Window:Tab({
    Title = "Minigames",
    Icon = "play",
    Locked = false,
})

Tab:Toggle({
    Title = "Auto Semir",
    Desc = "",
    Icon = "check",
    Type = "Checkbox",
    Value = false,
    Default = false,
    Callback = function(state)
        setSemir(state)
    end,
})

Tab:Toggle({
    Title = "Auto Ngamen",
    Desc = "",
    Icon = "check",
    Type = "Checkbox",
    Value = false,
    Default = false,
    Callback = function(state)
        setNgamen(state)
    end,
})

Tab:Toggle({
    Title = "Anti AFK",
    Desc = "",
    Icon = "check",
    Type = "Checkbox",
    Value = true,
    Default = true,
    Callback = function(state)
        setAntiAfk(state)
    end,
})

local FarmTab = Window:Tab({
    Title = "Farm",
    Icon = "trash-2",
    Locked = false,
})

FarmTab:Toggle({
    Title = "Auto Farm Rongsok",
    Desc = "",
    Icon = "check",
    Type = "Checkbox",
    Value = false,
    Default = false,
    Callback = function(state)
        setFarm(state)
    end,
})

FarmTab:Toggle({
    Title = "Avoid Players",
    Desc = "",
    Icon = "check",
    Type = "Checkbox",
    Value = true,
    Default = true,
    Callback = function(state)
        avoidOn = state
    end,
})

FarmTab:Slider({
    Title = "Avoid Radius",
    Desc = "",
    Step = 1,
    Value = {
        Min = 10,
        Max = 100,
        Default = 50,
    },
    Callback = function(value)
        avoidRadius = tonumber(value) or 50
    end,
})

-- Cleanup saat script dijalankan ulang
local function stopAll()
    alive = false
    setSemir(false)
    setNgamen(false)
    setFarm(false)
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if dotUi then dotUi:Destroy() end
    pcall(function() Window:Destroy() end)
end
if getgenv then getgenv().__HS_AutoMinigames_Stop = stopAll end

warn("[AutoMinigames] Siap. Nyalakan toggle di tab Minigames.")