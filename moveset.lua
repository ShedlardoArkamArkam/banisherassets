--!nocheck
-- ==================================================================
-- BANISHER ASSET LOADER (built in)
-- Checks the required mp3 files in your executor's workspace folder.
--   * all present  -> no GUI, the moveset below just starts
--   * some missing -> shows a download GUI on the right side of the screen,
--                     downloads only the missing files, then the moveset starts
-- ==================================================================
do
    local BASE_URL = "https://raw.githubusercontent.com/ShedlardoArkamArkam/banisherassets/refs/heads/main/"

    local ASSETS = {
        "EvoBanisher.mp3",
        "ImmortalityLord.mp3",
        "LightningCannon.mp3",
        "Relaxed.mp3",
        "SnakeBanisher.mp3",
        "RainbowBanisher.mp3",
        "Echo.mp3",
        "lcshoot.mp3",
        "GodCat.mp3",
    }

    local CHUNK_SIZE  = 512 * 1024       -- download piece size (smaller = smoother progress bar)
    local MAX_RETRIES = 3                -- tries per chunk / per file
    local ACCENT      = Color3.fromRGB(255, 40, 40)

    local Players      = game:GetService("Players")
    local TweenService = game:GetService("TweenService")

    local requestFn = (syn and syn.request) or http_request or request or (http and http.request) or (fluxus and fluxus.request)

    local function log(...)  print("[BanisherLoader]", ...) end
    local function warnf(...) warn("[BanisherLoader]", ...) end

    local gui = nil -- the loader GUI (kept here so an error can still clean it up)

    local function runLoader()
        ------------------------------------------------------------------
        -- CHECK WHAT IS MISSING
        ------------------------------------------------------------------
        if not (type(isfile) == "function" and type(writefile) == "function") then
            warnf("your executor does not support isfile/writefile - skipping the download step")
            return
        end

        local missing = {}
        for _, name in ipairs(ASSETS) do
            if not isfile(name) then table.insert(missing, name) end
        end

        if #missing == 0 then
            log("all assets already installed - launching")
            return
        end

        ------------------------------------------------------------------
        -- GUI
        ------------------------------------------------------------------
        local function make(class, props, parent)
            local inst = Instance.new(class)
            for k, v in pairs(props) do inst[k] = v end
            inst.Parent = parent
            return inst
        end

        local function guiParent()
            if type(gethui) == "function" then
                local ok, h = pcall(gethui)
                if ok and h then return h end
            end
            local ok, cg = pcall(function() return game:GetService("CoreGui") end)
            if ok and cg then
                local test = Instance.new("Folder")
                if pcall(function() test.Parent = cg end) and test.Parent == cg then
                    test:Destroy()
                    return cg
                end
            end
            return Players.LocalPlayer:WaitForChild("PlayerGui")
        end

        gui = make("ScreenGui", {
            Name = "BanisherLoader",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 999999,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, nil)
        if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
        gui.Parent = guiParent()

        local SHOWN  = UDim2.new(1, -20, 0.5, 0)
        local HIDDEN = UDim2.new(1, 340, 0.5, 0)

        local panel = make("Frame", {
            Name = "Panel",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = HIDDEN,
            Size = UDim2.fromOffset(320, 126),
            BackgroundColor3 = Color3.fromRGB(18, 18, 22),
            BorderSizePixel = 0,
        }, gui)
        make("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
        make("UIStroke", { Color = ACCENT, Thickness = 1.5, Transparency = 0.2 }, panel)

        local title = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(16, 12),
            Size = UDim2.new(1, -32, 0, 24),
            Font = Enum.Font.GothamBold,
            Text = "Downloading Required Assets",
            TextSize = 17,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextXAlignment = Enum.TextXAlignment.Left,
        }, panel)

        local assetLabel = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(16, 42),
            Size = UDim2.new(1, -32, 0, 20),
            Font = Enum.Font.Gotham,
            Text = "Current Asset : ",
            TextSize = 14,
            TextColor3 = Color3.fromRGB(200, 200, 210),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, panel)

        local barBack = make("Frame", {
            Position = UDim2.fromOffset(16, 72),
            Size = UDim2.new(1, -32, 0, 14),
            BackgroundColor3 = Color3.fromRGB(40, 40, 48),
            BorderSizePixel = 0,
        }, panel)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)

        local barFill = make("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = ACCENT,
            BorderSizePixel = 0,
        }, barBack)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, barFill)

        local percentLabel = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(16, 92),
            Size = UDim2.new(1, -32, 0, 20),
            Font = Enum.Font.GothamBold,
            Text = "0%",
            TextSize = 14,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextXAlignment = Enum.TextXAlignment.Left,
        }, panel)

        local countLabel = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(16, 92),
            Size = UDim2.new(1, -32, 0, 20),
            Font = Enum.Font.Gotham,
            Text = "",
            TextSize = 13,
            TextColor3 = Color3.fromRGB(150, 150, 160),
            TextXAlignment = Enum.TextXAlignment.Right,
        }, panel)

        local function tween(obj, time, props)
            TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
        end

        local function setProgress(fraction, text)
            fraction = math.clamp(fraction or 0, 0, 1)
            tween(barFill, 0.12, { Size = UDim2.new(fraction, 0, 1, 0) })
            percentLabel.Text = text or (math.floor(fraction * 100 + 0.5) .. "%")
        end

        local function setAsset(name, index, total)
            assetLabel.Text = "Current Asset : " .. name
            countLabel.Text = index .. "/" .. total
            setProgress(0)
        end

        tween(panel, 0.4, { Position = SHOWN })

        ------------------------------------------------------------------
        -- DOWNLOAD HELPERS
        ------------------------------------------------------------------
        local function getHeader(headers, name)
            if type(headers) ~= "table" then return nil end
            local lname = string.lower(name)
            for k, v in pairs(headers) do
                if string.lower(tostring(k)) == lname then return v end
            end
            return nil
        end

        local function looksLikeMp3(data)
            if type(data) ~= "string" or #data < 1024 then return false end
            if string.sub(data, 1, 3) == "ID3" then return true end
            local b1, b2 = string.byte(data, 1, 2)
            return b1 == 0xFF and b2 ~= nil and b2 >= 0xE0
        end

        -- downloads in pieces with Range requests so the real progress can be shown.
        -- returns data, or nil + error message
        local function downloadRanged(url, onProgress)
            local parts, got, total = {}, 0, nil
            while true do
                local res, lastErr
                for attempt = 1, MAX_RETRIES do
                    local ok, r = pcall(requestFn, {
                        Url = url,
                        Method = "GET",
                        Headers = { Range = "bytes=" .. got .. "-" .. (got + CHUNK_SIZE - 1) },
                    })
                    if ok and type(r) == "table" and type(r.Body) == "string" then
                        res = r
                        break
                    end
                    lastErr = ok and "bad response" or tostring(r)
                    task.wait(0.5 * attempt)
                end
                if not res then return nil, lastErr or "request failed" end

                local code = tonumber(res.StatusCode)
                if code == 200 then
                    -- server ignored the range and sent the whole file
                    onProgress(#res.Body, #res.Body)
                    return res.Body
                elseif code == 416 and got > 0 then
                    break -- asked past the end: we already have everything
                elseif code ~= 206 then
                    return nil, "HTTP " .. tostring(code)
                end

                local cr = getHeader(res.Headers, "Content-Range")
                local t = cr and tonumber(string.match(tostring(cr), "/(%d+)%s*$"))
                if t then total = t end

                parts[#parts + 1] = res.Body
                got = got + #res.Body
                onProgress(got, total)

                if #res.Body == 0 then return nil, "empty chunk" end
                if total and got >= total then break end
                if not total and #res.Body < CHUNK_SIZE then break end
            end

            local data = table.concat(parts)
            if total and #data ~= total then
                return nil, "size mismatch (" .. #data .. " of " .. total .. ")"
            end
            return data
        end

        -- fallback when the executor has no request function: no real progress available
        local function downloadSimple(url)
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if ok and type(res) == "string" then return res end
            return nil, tostring(res)
        end

        local function downloadAsset(name)
            local url = BASE_URL .. name
            local lastErr = "unknown error"
            for attempt = 1, MAX_RETRIES do
                local data, err
                if requestFn then
                    data, err = downloadRanged(url, function(got, total)
                        if total and total > 0 then
                            setProgress(got / total)
                        else
                            setProgress(0, "Downloading...")
                        end
                    end)
                else
                    setProgress(0, "Downloading...")
                    data, err = downloadSimple(url)
                end

                if data and looksLikeMp3(data) then
                    local ok, werr = pcall(writefile, name, data)
                    if ok then
                        setProgress(1)
                        return true
                    end
                    lastErr = "writefile failed: " .. tostring(werr)
                else
                    lastErr = err or "downloaded file is not a valid mp3"
                end
                warnf(("%s attempt %d/%d failed: %s"):format(name, attempt, MAX_RETRIES, lastErr))
                setProgress(0)
                task.wait(1)
            end
            return false, lastErr
        end

        ------------------------------------------------------------------
        -- RUN
        ------------------------------------------------------------------
        local failed = {}
        for i, name in ipairs(missing) do
            setAsset(name, i, #missing)
            local ok, err = downloadAsset(name)
            if not ok then
                table.insert(failed, name)
                warnf("giving up on " .. name .. ": " .. tostring(err))
            end
        end

        if #failed == 0 then
            title.Text = "Finished, Launching..."
            assetLabel.Text = ""
            countLabel.Text = ""
            setProgress(1, "100%")
        else
            title.Text = "Some assets failed, launching..."
            assetLabel.Text = "Failed: " .. table.concat(failed, ", ")
            countLabel.Text = ""
            percentLabel.Text = "see F9 console"
        end

        task.wait(failed[1] and 2.5 or 1.2)
        tween(panel, 0.4, { Position = HIDDEN })
        task.wait(0.5)
        gui:Destroy()
        gui = nil
    end

    local okLoader, errLoader = pcall(runLoader)
    if not okLoader then
        warnf("loader error: " .. tostring(errLoader) .. " - starting the moveset anyway")
        if gui then pcall(function() gui:Destroy() end) end
    end
end
-- ==================================================================
-- END OF ASSET LOADER - the moveset starts here
-- ==================================================================
--// PULSE REVOLVER - v2 (R6 ONLY) - PERFORMANCE OPTIMIZED
--// LocalScript -> StarterPlayer > StarterPlayerScripts
--// Full merged script based on the version supplied in chat.
--// Keeps: revolver model, pulse/muzzle colours, rainbow controls, animations,
--// shooting/hit effects, Orbit, Anti-Void, watched-animation void handoff,
--// full-avatar ghost, Roblox default camera following the ghost Humanoid,
--// WASD ghost movement, and delete UI. CameraType/CFrame/Focus are not overridden.
--// Performance changes: idempotent body hiding, throttled ghost animation sync,
--// no manual camera render-step, throttled void/Orbit writes,
--// throttled Anti-Void checks, and chunked ghost setup.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------
local CONFIG = {
    SCALE = 0.85,
    WALK_REF_SPEED = 16,
    IDLE2_AFTER = 5,
    IDLE2_COOLDOWN = 30,
    TAUNT_TIME = 2,
    SHOOT1_TIME = 0.7,
    SOUND_FIRE = 128799811976358,
    SOUND_TAUNT = 137716148492089,
    SOUND_FLOWING_FIRE = 137510557013265,
    FLOWING_FIRE_TIME = 0.5,
    FLOWING_KEY = Enum.KeyCode.R,
    FLOWING_BULLET_SIZE_MULTIPLIER = 2,
    FLOWING_BULLET_TIME_MULTIPLIER = 2,
    -- Aim-assist range = how many screen pixels from the cursor a target may be (per move)
    AIM_FOV = 80,           -- move 1 (E)
    AIM_FOV_FLOWING = math.huge, -- move 2 (R): maximum = any target on screen
    AIM_FOV_FLING = 120,    -- move 3 (V Fling)
    BULLET_THICKNESS = 0.12,
    BULLET_FADE_IN = 0.06,
    BULLET_HOLD = 0.3,
    BULLET_FADE_OUT = 0.2,
    HIT_FLASH_TIME = 0.6,
    HIT_FADE_TIME = 0.3,
    HIT_FLASH_RATE = 0.04,
    TAUNT_KEY = Enum.KeyCode.Y,
    SHOOT_KEY = Enum.KeyCode.E,
    GRIP_POINT = Vector3.new(0, -1.27, 1.12),
    PULSE_SEGMENTS = 36,
    PULSE_SPEED = 0.7,
    PULSE_TAIL = 2.6,
    TEETH_EVERY = 3,
    COLOR_PULSE = Color3.fromRGB(255, 40, 40),
    COLOR_MUZZLE = Color3.fromRGB(255, 40, 40),
    RAINBOW_SPEED = 0.25,
    FAILSAFE = { TIMEOUT = 1.0 }, -- no watched animation this many seconds after firing => orbit stops, we return to the clone
    THEME = {
        ENABLED = true,              -- false = no theme music at all
        FILE = "EvoBanisher.mp3",    -- file in your executor's workspace folder
        CACHE_FILE = "EvoBanisher_theme_cache.mp3", -- copy the script makes (writefile) and plays from, like your other script
        URL = "",                    -- optional direct link: if FILE is missing it gets downloaded and saved with writefile
        VOLUME = 0.5,                -- 0 = silent, 1 = normal, higher = louder
        SPEED = 1,                   -- playback speed (1 = normal, also changes pitch)
        LOOPED = true,               -- loop the song forever
        START_TIME = 0,              -- seconds into the song to start from
        FADE_IN = 1.5,               -- seconds to fade up to VOLUME when it starts
        FADE_OUT = 0.5,              -- seconds to fade out when the script is deleted
    },
    VISUALIZER = {
        ENABLED = true,
        BARS = 80,               -- parts in the ring at your feet
        RADIUS = 0,              -- studs from you to the INNER end of every bar (closest point to you); bars only grow outward from here
        BAR_WIDTH = 5.8,         -- exact width of every bar (no limit: wider bars overlap each other, thinner ones leave gaps)
        BAR_HEIGHT = 0.3,
        MIN_LENGTH = 0.1,        -- bar length when the song is quiet
        STRENGTH = 0.03,         -- how hard the bars grow with the song (no cap): length = MIN_LENGTH + loudness * STRENGTH
        ATTACK = 25,             -- how fast bars jump up with the beat
        RELEASE = 7,             -- how fast bars fall back down
        TRANSPARENCY = 0.1,
        GROUND_OFFSET = 0.12,    -- height above the floor
        LOUD_WHITE_AT = 850,     -- Immortality Lord: song loudness at which the visualizer reaches pure white (lower = whiter sooner)
    },
    PARTICLES = {
        ENABLED = true,
        MIN_RADIUS = 5,          -- spawn ring around you (studs)
        MAX_RADIUS = 30,
        SPAWN_MIN = 0.3,         -- seconds between particles (random between these)
        SPAWN_MAX = 0.6,
        LIFETIME_MIN = 2.5,
        LIFETIME_MAX = 4,
        RISE_MIN = 4,            -- studs per second going up
        RISE_MAX = 9,
        MAX_TILT = 18,           -- degrees: each particle drifts up and between this far left and this far right
        WIDTH = 0.3,             -- oval size
        LENGTH = 0.95,
        MAX_ACTIVE = 60,
    },
    ORBS = {
        ENABLED = true,
        SIZE = 0.22,             -- orb diameter
        RADIUS = 0.85,           -- how far they circle from the hand (the 2nd orb circles a bit wider)
        SPEED = 260,             -- degrees per second (the two orbs spin in opposite directions)
        FORWARD_OFFSET = 0.5,    -- how far in front of the hand the orbit is centered
        TRAIL_LIFETIME = 0.5,
        TRAIL_WIDTH = 0.3,
        FADE_IN = 0.8,
        FADE_OUT = 0.35,
        DEBUG = false,           -- true = prints the orb/idle state to the console every 2s
    },
    DELETE = {
        KEY = Enum.KeyCode.C,
        COOLDOWN = 1,            -- seconds before Delete can be used again
        RANGE = 2000,            -- tracer length (studs) when PIERCE_THROUGH is true (the visible tracer is capped at 2000, a part cannot be longer)
        PIERCE_THROUGH = true,   -- true: tracer keeps going past the cursor and hits everything in line; false: stops at the cursor
        MAX_PARTS = 500,         -- safety cap: parts one shot can delete
        SHAKE = 0.1,             -- studs of shake while fading
        FADE_OUT = 1.5,          -- seconds to fade away
        RESPAWN_TIME = 35,       -- seconds after the shot until the parts come back
        FADE_IN = 1.5,           -- seconds to fade back in
        IGNORE_FOLDERS = { "Live", "Players" }, -- children of Workspace the tracer may never touch (player characters are always ignored too)
        pending = false, registry = {}, count = 0, readyAt = 0,
    },
    IDLE = { state1 = {}, state2 = {} },
    REPLACE = { map = {}, tracks = {}, loading = {}, lastTrigger = {}, started = {} },
    MODES = {
        SWITCH_KEY = Enum.KeyCode.M,
        SWITCH_SOUND = 4836187667,
        SWITCH_VOLUME = 1.5,
        MOVE_LINES_USE_FONT = false, -- true = the E/R/T/Y/V/C/M lines use the mode font too (default: only the title + name above your head)
        index = 1,
        -- per mode:  text / cylinder / tip / song / font
        --   visualizerStrength = how hard the visualizer ring grows with THIS mode's song (no cap)
        --   idle / idle2       = idle animations + pattern (see "IDLE PATTERNS" lower down); leave out to use the default idles
        --   replace            = { [animation the game plays] = animation we play instead }
        list = {
            { text = "Evo Banisher", cylinder = Color3.fromRGB(255, 110, 110), tip = Color3.fromRGB(255, 110, 110),
              song = "EvoBanisher.mp3", font = Enum.Font.Arcade, visualizerStrength = 0.03 },

            { text = "Immortality Lord", cylinder = Color3.fromRGB(0, 0, 0), tip = Color3.fromRGB(0, 0, 0),
              song = "ImmortalityLord.mp3", font = Enum.Font.SpecialElite, loudnessColor = true, visualizerStrength = 0.03,
              gun = "sword", -- holds the ImmortalityLord sword instead of the revolver
              noWalkAnim = true, -- no walk animation: the idle animation keeps playing while walking
              idle = { id = "15099756132", kind = "loop" },
              moves = {
                  -- E and C share this animation; the sword check happens fireTime seconds into it
                  shoot = { id = "15240176873", fireTime = 0.4 },
                  -- R: skip the first startTime seconds, play to the end; the R code runs fireDelay seconds after it starts
                  flowing = { id = "15145462680", startTime = 2, fireDelay = 0 } } },

            { text = "Lightning Cannon", cylinder = Color3.fromRGB(255, 255, 255), tip = Color3.fromRGB(190, 190, 195),
              song = "LightningCannon.mp3", font = Enum.Font.Oswald, visualizerStrength = 0.03,
              gun = "railgun", -- holds the railgun instead of the revolver
              idle = { id = "110359958284400", kind = "segmentLoop", from = 0, to = 0, }, -- only the start of it, looped (to = where "the start" ends, in seconds)
              replace = { ["13532562418"] = "111644455066361", ["13532600125"] = "112778933066374" } },

            { text = "Relaxed", cylinder = Color3.fromRGB(140, 205, 255), tip = Color3.fromRGB(140, 205, 255),
              song = "Relaxed.mp3", font = Enum.Font.Arcade, visualizerStrength = 0.03,
              noWalkAnim = true, -- no walk animation: the idle animation keeps playing while walking
              idle = { id = "15503060948", kind = "loop" },
              idle2 = { id = "17106169665", kind = "segmentOnce", from = 1, to = 2.8 } },

            { text = "Snake Banisher", cylinder = Color3.fromRGB(255, 0, 0), tip = Color3.fromRGB(255, 0, 0),
              song = "SnakeBanisher.mp3", font = Enum.Font.Merriweather, visualizerStrength = 0.03,
              idle = { id = "15503060232", kind = "pingpong", from = 0.75, to = 0.77, waitEnd = 0.1, waitStart = 0.1 }, -- same pattern as Echo's idle
              idle2 = { id = "15488553333", kind = "segmentOnce", from = 0.3, to = 2.5, waitEnd = 0, waitStart = 0, once = true } },

            { text = "Rainbow Banisher", rainbow = true,
              song = "RainbowBanisher.mp3", font = Enum.Font.Arcade, visualizerStrength = 0.03,
              idle2 = { id = "73949048256257", kind = "segmentOnce", from = 8.9, to = 14.2 } },

            { text = "Echo", cylinder = Color3.fromRGB(48, 22, 22), tip = Color3.fromRGB(48, 22, 22),
              song = "Echo.mp3", font = Enum.Font.SpecialElite, visualizerStrength = 0.03,
              gun = "rust", -- holds the rusted gun instead of the revolver
              idle = { id = "15311685628", kind = "pingpong", from = 0.75, to = 0.867, waitEnd = 1, waitStart = 0 },
              replace = { ["15162694192"] = "13378708199" } },

            -- GOD CAT: no custom weapon (normal revolver), horns on the body + clone, visualizer flickers black/white shades
            { text = "God Cat", cylinder = Color3.fromRGB(255, 255, 255), tip = Color3.fromRGB(255, 255, 255),
              song = "GodCat.mp3", font = Enum.Font.SourceSansItalic, visualizerStrength = 0.03,
              godCat = true, -- horns + black/white shade flicker (see CONFIG.GODCAT)
              noWalkAnim = true, -- the idle keeps playing while walking
              -- idle: the whole animation, looped (both idle animations are on Action3)
              idle = { id = "15099756132", kind = "loop", priority = Enum.AnimationPriority.Action3 },
              -- idleLayer: a SECOND idle that plays at the same time, held on one frame (from = to = frozen pose at 0.9s)
              idleLayer = { id = "15284324734", from = 0.9, to = 0.9, priority = Enum.AnimationPriority.Action3 } },
        },
    },
    -- God Cat settings: horn shape + how fast the black/white shades change
    GODCAT = {
        FLICKER_RATE = 0.05,     -- seconds between colour changes (horns + visualizer). Lower = faster
        -- every shade the horns + visualizer can switch between (0 = pure black, 1 = pure white).
        -- add / remove numbers to change the variety (more grays in the middle = more gray flicker)
        SHADES = { 0, 0.06, 0.12, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.88, 0.95, 1 },
        HORN_SEGMENTS = 15,      -- more = smoother curve
        HORN_SEG_LENGTH = 0.215, -- length per segment (a bit taller than before)
        HORN_BASE_RADIUS = 0.17, -- thickness at the base
        HORN_TIP_RADIUS = 0.02,  -- thickness at the tip
        HORN_START_ANGLE = 35,   -- degrees leaning FORWARD at the base
        HORN_END_ANGLE = -65,    -- degrees leaning BACKWARD at the tip
        HORN_OUTWARD = 6,        -- slight sideways splay (degrees)
        HORN_SIDE_OFFSET = 0.4,  -- distance from the head's centre
        HORN_FRONT_OFFSET = -0.3, -- negative = front of the head
    },
    PROFILE = false, -- set true to print per-callback cost (ms) every 3s in the output/F9 console
}

local BODY = Color3.fromRGB(26, 30, 40)
local BODY2 = Color3.fromRGB(46, 52, 68)
local SC = CONFIG.SCALE
local BLACK = Color3.new(0, 0, 0)
local M = Enum.Material
local ZAXIS = CFrame.Angles(0, math.pi / 2, 0)
local GRIP_C0 = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

------------------------------------------------------------------
-- GENERAL STATE
------------------------------------------------------------------
local model, root = nil, nil
local gui, panel, visibilityButton = nil, nil, nil
local deleteAll
local connection, charConn, inputConn, ghostInputEndedConn = nil, nil, nil, nil
local deleted = false
local segments, muzzleParts, muzzleSeq, muzzleLights = {}, {}, {}, {}
local muzzleZone = nil
local pulsePhase, pulseSpeed = 0, CONFIG.PULSE_SPEED
local rainbowSpeed, rainbowPhase = CONFIG.RAINBOW_SPEED, 0
local previews = {}
local colors = { pulse = CONFIG.COLOR_PULSE, muzzle = CONFIG.COLOR_MUZZLE }
local rainbow = { pulse = false, muzzle = false }
local live = { pulse = CONFIG.COLOR_PULSE, muzzle = CONFIG.COLOR_MUZZLE }

------------------------------------------------------------------
-- PERF HELPERS (optional profiler + small shared caches)
------------------------------------------------------------------
local Perf = { idleStopAt = setmetatable({}, { __mode = "k" }), acc = {}, rainbowAcc = 0, pulseAcc = 0, revolverOnGhost = false, reportConn = nil, frames = 0, since = os.clock() }
-- Leave-one-out stages for the P test. Pieces: revolver (revolver carried by ghost),
-- sync (ghost animation sync + movement), camera (camera swap), hide (real body hidden).
Perf.STAGES = {
    { name = "1: FULL (reference)",                         revolver = true, sync = true, camera = true, hide = true },
    { name = "2: FULL without revolver-on-ghost",           sync = true, camera = true, hide = true },
    { name = "3: FULL without animation sync/movement",     revolver = true, camera = true, hide = true },
    { name = "4: FULL without hiding the real body",        revolver = true, sync = true, camera = true },
    { name = "5: FULL without camera swap (and no hide)",   revolver = true, sync = true },
    { name = "6: camera + revolver only",                   revolver = true, camera = true },
    { name = "7: camera + sync only",                       sync = true, camera = true },
}
-- nil stage = normal behaviour (everything on); only the P test sets a stage
function Perf.on(flag)
    local st = Perf.stage
    return st == nil or st[flag] == true
end

function Perf.wrap(name, fn)
    if not CONFIG.PROFILE then return fn end
    return function(...)
        local t0 = os.clock()
        local a, b, c = fn(...)
        local dt = os.clock() - t0
        local e = Perf.acc[name]
        if not e then e = { total = 0, calls = 0, max = 0 } Perf.acc[name] = e end
        e.total += dt e.calls += 1
        if dt > e.max then e.max = dt end
        return a, b, c
    end
end
if CONFIG.PROFILE then
    Perf.reportConn = RunService.Heartbeat:Connect(function()
        Perf.frames += 1
        local now = os.clock()
        if now - Perf.since < 3 then return end
        local elapsed = now - Perf.since
        local lines = { string.format("[PulseRevolver][perf] %.0f FPS | ghost=%s orbit=%s | test stage: %s", Perf.frames / elapsed, tostring(Perf.ghostAlive), tostring(Perf.orbitOn), Perf.stage and Perf.stage.name or "off") }
        for name, e in pairs(Perf.acc) do
            table.insert(lines, string.format("  %-14s avg %.3f ms/call  max %.2f ms  %.0f calls/s  => %.2f ms/s",
                name, e.total / math.max(e.calls, 1) * 1000, e.max * 1000, e.calls / elapsed, e.total / elapsed * 1000))
            e.total, e.calls, e.max = 0, 0, 0
        end
        local Stats = game:GetService("Stats")
        local function stat(name)
            local ok, v = pcall(function() return Stats[name] end)
            return (ok and type(v) == "number") and v or nil
        end
        local function fmt(v, f) return v and string.format(f, v) or "n/a" end
        local gpu, cpu
        pcall(function() gpu = Stats.PerformanceStats.GPU:GetValue() end)
        pcall(function() cpu = Stats.PerformanceStats.CPU:GetValue() end)
        table.insert(lines, string.format("  ENGINE  heartbeat %s ms | physics %s ms | frameCPU %s ms | frameGPU %s ms",
            fmt(stat("HeartbeatTimeMs"), "%.2f"), fmt(stat("PhysicsStepTimeMs"), "%.2f"), fmt(cpu, "%.2f"), fmt(gpu, "%.2f")))
        table.insert(lines, string.format("  ENGINE  parts %s | moving %s | contacts %s | instances %s",
            fmt(stat("PrimitivesCount"), "%d"), fmt(stat("MovingPrimitivesCount"), "%d"),
            fmt(stat("ContactsCount"), "%d"), fmt(stat("InstanceCount"), "%d")))
        print(table.concat(lines, "\n"))
        Perf.frames, Perf.since = 0, now
    end)
end

------------------------------------------------------------------
-- ANIMATIONS
------------------------------------------------------------------
local ANIM = {
    WALK = "rbxassetid://15962326593",
    IDLE = "rbxassetid://15020965094",
    IDLE2 = "rbxassetid://14348083862",
    TAUNT = "rbxassetid://8887084105",
    SHOOT1 = "rbxassetid://17097146599",
    FLOWING = "rbxassetid://17097068597",
}

local animator, animHum, animHrp, animateScript = nil, nil, nil, nil
local animReady, animToken = false, 0
local trk = {}
local want, wantSpeed, lastTime, ours = {}, {}, {}, {}
local ghostHandoffTracks, animConns = {}, {}
local ov, stillTime, idle2ReadyAt, idleHeld = nil, 0, 0, false

------------------------------------------------------------------
-- ORBIT / ANTI-VOID / GHOST CONFIG + STATE
------------------------------------------------------------------
local ORBIT_DISTANCE = 3
local ORBIT_HEIGHT = 0
local ORBIT_OFFSET_SPACE = "Target Local"
local VOID_Y = -2000
local WATCHED_ANIMATION_ID = "12296113986"
local ORBIT_TOOL_NAME = "Lethal Whirlwind Stream"
CONFIG.FLOW = {
    animationId = "12273188754",
    toolName = ORBIT_TOOL_NAME,
    flowingToolName = "Flowing Water",
    active = false,
    fired = false,
    toolWarned = false,
    destination = nil,
}
CONFIG.FLING = {
    KEY = Enum.KeyCode.V,
    ANIMATION_ID = "rbxassetid://17863045150", -- PLACEHOLDER: put the Fling animation id here (e.g. "rbxassetid://123456")
    SOUND_ID = 0,                    -- PLACEHOLDER: put the Fling sound id here (e.g. 123456789)
    TOOL_NAME = "",                  -- optional tool to equip briefly while flinging ("" = none)
    DISTANCE_FAR = -1,                -- orbit distance at the start of every lap (behind the target)
    DISTANCE_NEAR = -2.5,              -- orbit distance at the other end of the lap (in front of the target)
    LAP_TIME = 0.015,                  -- seconds per lap
    LAPS = 150,                        -- laps before the move finishes
    ROUND_TRIP = false,               -- true: a lap goes 3 -> -3 -> 3 ; false: 3 -> -3 then snaps back to 3
    MAX_DURATION = 3,                -- safety: abort if the sweep has not finished after this many seconds
    USE_Y_POS = true,               -- false: sweep front/back (behind <-> in front). true: sweep up/down on the Y axis instead
    Y_FORWARD = 0,                   -- only used when USE_Y_POS = true: fixed front/back offset (0 = straight through the target)
    ROTATION_SPEED = 108000,           -- degrees per second our character spins while the sweep runs (no laps, just speed)
    ROTATION_CHANGE_TIME = 0,     -- seconds between picking a new random spin direction (0 = keep one random direction)
    active = false, startedAt = nil, sweepStart = nil,
    rotation = nil, axis = nil, axisAt = 0,
}
-- P key = ATTACK MODE (changes how the E move works)
--   Kill   : E sends us to VOID_Y (-2000, the default)
--   Banish : E sends us to BANISH_Y (a really big number, high above the map)
CONFIG.ATTACK = {
    KEY = Enum.KeyCode.P,
    KILL_Y = -100,    -- the default void height
    BANISH_Y = 10000000,     -- Banish height (raise it for an even bigger number)
    modes = { "Kill" },
    index = 1,          -- starts on Kill
}
CONFIG.ATTACK.mode = function() return CONFIG.ATTACK.modes[CONFIG.ATTACK.index] end
CONFIG.ATTACK.voidY = function()
    local A = CONFIG.ATTACK
    return A.mode() == "Banish" and A.BANISH_Y or A.KILL_Y
end

-- L key = BRING MODE (changes how the R move works)
--   Kill   : like E's void trip (VOID_Y) but with R's animation, then back to the clone
--   Bring  : the original R move (teleports us to the clone when finished)
--   Banish : like Kill but up at BANISH_Y, then back to the clone
CONFIG.BRING = {
    KEY = Enum.KeyCode.L,
    modes = {"Bring", "Banish" },
    index = 2,          -- starts on Bring = the original R move
    locked = nil,       -- the mode R started with (a mode change mid-move does not affect it)
}
CONFIG.BRING.mode = function()
    local B = CONFIG.BRING
    if CONFIG.FLOW.active and B.locked then return B.locked end
    return B.modes[B.index]
end
CONFIG.BRING.useVoid = function() return CONFIG.BRING.mode() ~= "Bring" end
CONFIG.BRING.voidY = function()
    return CONFIG.BRING.mode() == "Banish" and CONFIG.ATTACK.BANISH_Y or CONFIG.ATTACK.KILL_Y
end

-- Each move owns its own cooldown state. Equipping one move's tool must not
-- put the other move on cooldown.
local MOVE_COOLDOWNS = {
    primary = { duration = 20, untilTime = 0, pending = false, epoch = 0 },
    flowing = { duration = 18, untilTime = 0, pending = false, epoch = 0 },
}
local cooldownDeathConnection = nil
local sethidden = sethiddenproperty
local orbitEnabled, orbitStatus = false, "disabled"
local orbitConnection, characterConnection2 = nil, nil
local engaged, engagedChar = false, nil
local lastWorldCF, orbitWorldCF = nil, nil
local lastSpace, lastInfo = 0, ""
local shotTargetModel = nil
local orbitAccumulator = 0
local ORBIT_UPDATE_INTERVAL = 1 / 30

local ghostFolder = Instance.new("Folder")
ghostFolder.Name = "PRevolverOrbitGhosts"
ghostFolder.Parent = workspace
local ghostModel, ghostSource, ghostHumanoid, ghostRoot, ghostHead = nil, nil, nil, nil, nil
local ghostNeutralHeadOffset, ghostAnimator = nil, nil
local ghostTrackMap, ghostWalkTrack = {}, nil
local ghostWorldCF, ghostExpectedCFrame = nil, nil
local realBodyHidden, realBodyTransparency = false, {}
local realBodyHiddenCharacter = nil
local realBodyDescendantConn = nil
-- The Roblox camera controller remains in charge. We only swap CameraSubject.
local ghostPreviousCameraSubject = nil
local ghostCameraSaved = false
local ghostBuildRetryAt, ghostLastBuildError = 0, nil
local ghostBuildInProgress = false
local ghostMoveKeys = {
    [Enum.KeyCode.W] = false,
    [Enum.KeyCode.A] = false,
    [Enum.KeyCode.S] = false,
    [Enum.KeyCode.D] = false,
}
local ghostRenderConnection = nil
local ghostAnimationSyncInterval = 1 / 20
local ghostAnimationSyncAt = 0

local AV = {
    enabled = false,
    BIGGEST = -3.4e38,
    hookTried = false,
    blocked = 0,
    applied = nil,
    origHeight = nil,
    origFall = nil,
    conn = nil,
}

local diagnosticStatus = "Waiting for Orbit + Anti Void"
local diagnosticLastOutcome = "None yet"
local diagnosticTrack, diagnosticLastHandledTrack = nil, nil
local diagnosticTarget, diagnosticTargetHumanoid = nil, nil
local diagnosticConnections = {}
local diagnosticAccumulator, diagnosticConnection = 0, nil
local animationVoidTrip, voidReferenceConnection = nil, nil
local shotReturnCFrame = nil
local beginAnimationVoidTrip, endAnimationVoidTrip

------------------------------------------------------------------
-- CHARACTER HELPERS
------------------------------------------------------------------
local function getCharacter()
    return player.Character
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local char = getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function resetToolCooldown()
    for _, state in pairs(MOVE_COOLDOWNS) do
        state.epoch += 1
        state.untilTime = 0
        state.pending = false
    end
end

local function isToolOnCooldown(moveKey)
    local state = MOVE_COOLDOWNS[moveKey or "primary"]
    return state ~= nil and (state.pending or os.clock() < state.untilTime) or false
end

local function setOrbitStatus(value)
    orbitStatus = value
end

local function setHidden(inst, prop, value)
    if sethidden then
        local ok = pcall(sethidden, inst, prop, value)
        if ok then return end
    end
    pcall(function() inst[prop] = value end)
end

local animationIdCache = setmetatable({}, { __mode = "k" })
local function animationIdOf(track)
    if not track then return nil end
    local cached = animationIdCache[track]
    if cached ~= nil then return cached or nil end
    local animation = track.Animation
    if not animation then return nil end
    local raw = tostring(animation.AnimationId or "")
    local id = raw:match("(%d+)$") or raw:match("(%d+)")
    animationIdCache[track] = id or false
    return id
end

local function isVoidAnimOurs(track)
    local id = animationIdOf(track)
    return id == WATCHED_ANIMATION_ID or id == CONFIG.FLOW.animationId
end

local function isValidShotTarget(targetModel)
    return targetModel ~= nil and targetModel:IsA("Model")
        and targetModel:IsDescendantOf(workspace) and targetModel ~= getCharacter()
end

local function findShotTarget()
    if isValidShotTarget(shotTargetModel) then return shotTargetModel end
    shotTargetModel = nil
    return nil
end

local function resolveOrbitTarget()
    return findShotTarget()
end

local function equipToolBriefly(character, humanoid, tool, moveKey)
    local state = MOVE_COOLDOWNS[moveKey or "primary"]
    if not state or state.pending or os.clock() < state.untilTime or deleted then return false end
    if not character or character ~= player.Character or not humanoid or humanoid.Health <= 0 then return false end
    if not tool or not tool:IsA("Tool") then return false end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if tool.Parent ~= character and tool.Parent ~= backpack then return false end

    state.pending = true
    local thisEpoch = state.epoch
    local ok = pcall(function() humanoid:EquipTool(tool) end)
    if not ok then
        if thisEpoch == state.epoch then state.pending = false end
        return false
    end

    task.spawn(function()
        local deadline = os.clock() + 0.75
        while thisEpoch == state.epoch and not deleted and player.Character == character
            and humanoid.Parent == character and tool.Parent ~= character and os.clock() < deadline do
            RunService.Heartbeat:Wait()
        end
        if thisEpoch ~= state.epoch then return end
        if deleted or player.Character ~= character or humanoid.Parent ~= character
            or humanoid.Health <= 0 or tool.Parent ~= character then
            state.pending = false
            return
        end
        task.wait(0.1)
        if thisEpoch ~= state.epoch then return end
        if player.Character == character and humanoid.Parent == character and humanoid.Health > 0 then
            if tool.Parent == character then
                pcall(function() humanoid:UnequipTools() end)
            end
            -- Start only this move's cooldown after its tool was confirmed equipped.
            state.untilTime = os.clock() + state.duration
        end
        state.pending = false
    end)
    return true
end

------------------------------------------------------------------
-- DIAGNOSTIC WATCH + ANIMATION DETECTION
------------------------------------------------------------------
local function disconnectDiagnosticConnections()
    for _, conn in ipairs(diagnosticConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(diagnosticConnections)
end

local function finishDiagnosticWatch(reason)
    if not diagnosticTrack and not diagnosticTarget then
        diagnosticStatus = reason or diagnosticStatus
        return
    end
    disconnectDiagnosticConnections()
    if endAnimationVoidTrip then endAnimationVoidTrip(reason or "Diagnostic monitor ended") end
    -- R in Bring Mode Kill / Banish: if the void trip never started (e.g. no valid target), still return to the clone
    if CONFIG.FLOW.active and not animationVoidTrip and CONFIG.FLOW.finish then
        CONFIG.FLOW.finish(reason or "Diagnostic monitor ended")
    end
    if diagnosticTrack then diagnosticLastHandledTrack = diagnosticTrack end
    diagnosticTrack, diagnosticTarget, diagnosticTargetHumanoid = nil, nil, nil
    diagnosticStatus = reason or "Monitor ended"
    diagnosticLastOutcome = diagnosticStatus
end

local function startDiagnosticWatch(track)
    disconnectDiagnosticConnections()
    diagnosticTrack = track
    CONFIG.FAILSAFE.deadline = nil -- animation detected: failsafe not needed
    diagnosticTarget = findShotTarget()
    diagnosticTargetHumanoid = diagnosticTarget and diagnosticTarget:FindFirstChildOfClass("Humanoid") or nil

    -- Bring Mode "Bring" = the original R move (straight back to the clone).
    -- Bring Mode "Kill" / "Banish" skip this and use the same void trip E uses (below), with R's animation.
    if animationIdOf(track) == CONFIG.FLOW.animationId and not (CONFIG.FLOW.active and CONFIG.BRING.useVoid()) then
        diagnosticStatus = "Flowing Water animation detected; returning to shot position"
        diagnosticLastHandledTrack = track
        if CONFIG.FLOW.finish then CONFIG.FLOW.finish("Flowing Water animation detected") end
        table.insert(diagnosticConnections, track.Stopped:Connect(function()
            if diagnosticTrack == track then finishDiagnosticWatch("Flowing Water animation ended") end
        end))
        return
    end

    if diagnosticTarget and diagnosticTargetHumanoid then
        diagnosticStatus = "Animation detected; watching target"
        table.insert(diagnosticConnections, diagnosticTargetHumanoid.HealthChanged:Connect(function(health)
            if health <= 0 then finishDiagnosticWatch("Target reached 0 health") end
        end))
        table.insert(diagnosticConnections, diagnosticTarget.AncestryChanged:Connect(function(_, parent)
            if parent == nil then finishDiagnosticWatch("Target was deleted") end
        end))
    else
        diagnosticStatus = "Animation detected; target not found"
    end
    if beginAnimationVoidTrip then beginAnimationVoidTrip(track, diagnosticTarget, diagnosticTargetHumanoid) end
    table.insert(diagnosticConnections, track.Stopped:Connect(function()
        if diagnosticTrack == track then finishDiagnosticWatch("Animation ended before target died") end
    end))
end

local function findWatchedAnimation()
    -- Check our own Animator first, then the currently selected target's Animator.
    -- This supports games that play the move marker on either character.
    local hum = getHumanoid()
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if anim then
        for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
            local id = animationIdOf(track)
            if track.IsPlaying and (id == WATCHED_ANIMATION_ID or id == CONFIG.FLOW.animationId) then
                return track
            end
        end
    end

    local target = findShotTarget()
    local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
    local targetAnimator = targetHumanoid and targetHumanoid:FindFirstChildOfClass("Animator")
    if targetAnimator then
        for _, track in ipairs(targetAnimator:GetPlayingAnimationTracks()) do
            local id = animationIdOf(track)
            if track.IsPlaying and (id == WATCHED_ANIMATION_ID or id == CONFIG.FLOW.animationId) then
                return track
            end
        end
    end
    return nil
end

local function updateDiagnostics(dt)
    diagnosticAccumulator += dt
    if diagnosticAccumulator < 0.1 then return end
    diagnosticAccumulator = 0
    if CONFIG.FLING.active then
        if CONFIG.FLING.startedAt and os.clock() - CONFIG.FLING.startedAt > CONFIG.FLING.MAX_DURATION then
            CONFIG.FLING.finish("Fling timed out")
        end
        return
    end
    local failsafe = CONFIG.FAILSAFE
    if failsafe.deadline then
        if not orbitEnabled or animationVoidTrip or diagnosticTrack then
            failsafe.deadline = nil
        elseif os.clock() >= failsafe.deadline then
            failsafe.deadline = nil
            failsafe.returnToClone("Failsafe: watched animation not detected within " .. tostring(failsafe.TIMEOUT) .. "s; returned to clone")
            return
        end
    end
    if not AV.enabled or (not orbitEnabled and not animationVoidTrip) then
        if diagnosticTrack or diagnosticTarget then
            finishDiagnosticWatch("Monitoring stopped: enable Orbit + Anti Void")
        else
            diagnosticStatus = "Waiting for Orbit + Anti Void"
        end
        return
    end
    if diagnosticTarget then
        if not diagnosticTarget:IsDescendantOf(workspace) then
            finishDiagnosticWatch("Target was deleted")
            return
        end
        if diagnosticTargetHumanoid and diagnosticTargetHumanoid.Health <= 0 then
            finishDiagnosticWatch("Target reached 0 health")
            return
        end
    elseif diagnosticTrack then
        local newlyFound = findShotTarget()
        if newlyFound then
            diagnosticTarget = newlyFound
            diagnosticTargetHumanoid = newlyFound:FindFirstChildOfClass("Humanoid")
            if diagnosticTargetHumanoid then
                diagnosticStatus = "Animation detected; watching target"
                table.insert(diagnosticConnections, diagnosticTargetHumanoid.HealthChanged:Connect(function(health)
                    if health <= 0 then finishDiagnosticWatch("Target reached 0 health") end
                end))
                table.insert(diagnosticConnections, newlyFound.AncestryChanged:Connect(function(_, parent)
                    if parent == nil then finishDiagnosticWatch("Target was deleted") end
                end))
                if beginAnimationVoidTrip then beginAnimationVoidTrip(diagnosticTrack, diagnosticTarget, diagnosticTargetHumanoid) end
            end
        end
    end
    local currentTrack = findWatchedAnimation()
    if currentTrack then
        if currentTrack ~= diagnosticTrack and currentTrack ~= diagnosticLastHandledTrack then
            startDiagnosticWatch(currentTrack)
        end
    elseif diagnosticTrack then
        finishDiagnosticWatch("Animation ended before target died")
    else
        diagnosticLastHandledTrack = nil
        diagnosticStatus = "Armed; waiting for animation " .. WATCHED_ANIMATION_ID .. " or " .. CONFIG.FLOW.animationId
    end
end

------------------------------------------------------------------
-- ORBIT / VOID POSITIONING
------------------------------------------------------------------
local function offsetBehind(targetRoot, up, forward)
    local _, ry, _ = targetRoot.CFrame:ToEulerAnglesYXZ()
    local yaw = CFrame.fromEulerAnglesYXZ(0, ry, 0)
    local pos = (CFrame.new(targetRoot.Position) * yaw * CFrame.new(0, up, forward)).Position
    return CFrame.new(pos) * yaw
end

local function release(keepCFrame)
    if not engaged then orbitWorldCF = nil return end
    engaged = false
    orbitWorldCF = nil
    local char = engagedChar
    engagedChar = nil
    if not char or char ~= player.Character then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hum then
        hum.AutoRotate = true
        setHidden(hum, "PlatformStand", false)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    if hrp then
        setHidden(hrp, "PhysicsRepRootPart", hrp)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if lastWorldCF and not keepCFrame then hrp.CFrame = lastWorldCF end
    end
end

function AV.protecting()
    return (not deleted) and (AV.enabled or orbitEnabled) and true or false
end
function AV.desiredHeight()
    if deleted then return nil end
    if AV.enabled or orbitEnabled then return AV.BIGGEST end
    return nil
end
function AV.installHook()
    if AV.hookTried then return end
    AV.hookTried = true
    if type(hookmetamethod) ~= "function" then
        warn("[AntiVoid] hookmetamethod unavailable - only destroy height is changed")
        return
    end
    local old
    local hookFunction = function(self, key, value)
        if key == "Health" and value == 0 and AV.protecting() then
            local hum, hrp = getHumanoid(), getRoot()
            if self == hum and hrp and hrp.Parent and hrp.Position.Y < -500 then
                AV.blocked += 1
                return
            end
        end
        return old(self, key, value)
    end
    if type(newcclosure) == "function" then hookFunction = newcclosure(hookFunction) end
    local ok, result = pcall(hookmetamethod, game, "__newindex", hookFunction)
    if ok then old = result else warn("[AntiVoid] hook failed: " .. tostring(result)) end
end
function AV.apply(height)
    if height ~= nil then
        if AV.origHeight == nil then
            AV.origHeight = workspace.FallenPartsDestroyHeight
            pcall(function() AV.origFall = workspace.FallHeightEnabled end)
        end
        local current = workspace.FallenPartsDestroyHeight
        if AV.applied ~= height or math.abs(current - height) > math.abs(height) * 1e-5 then
            pcall(function() workspace.FallenPartsDestroyHeight = height end)
        end
        pcall(function()
            if workspace.FallHeightEnabled ~= false then workspace.FallHeightEnabled = false end
        end)
        AV.applied = height
    elseif AV.applied ~= nil or AV.origHeight ~= nil then
        if AV.origHeight ~= nil then pcall(function() workspace.FallenPartsDestroyHeight = AV.origHeight end) end
        if AV.origFall ~= nil then pcall(function() workspace.FallHeightEnabled = AV.origFall end) end
        AV.origHeight, AV.origFall, AV.applied = nil, nil, nil
    end
end
function AV.setEnabled(on)
    AV.enabled = on and true or false
end
function AV.cleanup()
    AV.enabled = false
    if AV.conn then AV.conn:Disconnect() AV.conn = nil end
    AV.apply(nil)
end
if type(setscriptable) == "function" then
    pcall(setscriptable, workspace, "FallenPartsDestroyHeight", true)
    pcall(setscriptable, workspace, "FallHeightEnabled", true)
end
local antiVoidApplyAccumulator = 0
AV.conn = RunService.Heartbeat:Connect(function(dt)
    if deleted then return end
    antiVoidApplyAccumulator += dt
    if antiVoidApplyAccumulator < 0.1 then return end
    antiVoidApplyAccumulator = 0
    local wantedHeight = AV.desiredHeight()
    if wantedHeight ~= nil then AV.installHook() end
    AV.apply(wantedHeight)
end)

------------------------------------------------------------------
-- FULL AVATAR GHOST + CAMERA
------------------------------------------------------------------
local function setRealBodyHidden(char, hidden)
    if hidden then
        if not char then return end
        if realBodyHidden and realBodyHiddenCharacter == char then return end
        if realBodyDescendantConn then realBodyDescendantConn:Disconnect() realBodyDescendantConn = nil end
        if realBodyHidden and realBodyHiddenCharacter ~= char then
            for part, previous in pairs(realBodyTransparency) do
                if part and part.Parent then part.LocalTransparencyModifier = previous end
                realBodyTransparency[part] = nil
            end
        end
        realBodyHidden = true
        realBodyHiddenCharacter = char
        local function hidePart(descendant)
            if descendant:IsA("BasePart") then
                if realBodyTransparency[descendant] == nil then
                    realBodyTransparency[descendant] = descendant.LocalTransparencyModifier
                end
                descendant.LocalTransparencyModifier = 1
            end
        end
        for _, descendant in ipairs(char:GetDescendants()) do hidePart(descendant) end
        realBodyDescendantConn = char.DescendantAdded:Connect(hidePart)
    else
        if not realBodyHidden and next(realBodyTransparency) == nil then return end
        realBodyHidden = false
        realBodyHiddenCharacter = nil
        if realBodyDescendantConn then realBodyDescendantConn:Disconnect() realBodyDescendantConn = nil end
        for part, previous in pairs(realBodyTransparency) do
            if part and part.Parent then part.LocalTransparencyModifier = previous end
            realBodyTransparency[part] = nil
        end
    end
end

-- Keep Roblox's built-in camera controller untouched. The ghost Humanoid is
-- the only thing we swap: Roblox continues handling orbit, zoom, sensitivity,
-- mouse behavior, and the active camera mode.
--
-- FIX: the subject is only handed to Roblox once the clone's Humanoid has a
-- RootPart (otherwise the camera controller has nothing to follow and stays on
-- the old position), and it is re-asserted right BEFORE the camera update every
-- frame so nothing can snap it back to the real Humanoid for a frame.
local GhostCam = { bound = false, changedConn = nil, changedCamera = nil }
local GHOST_CAMERA_BIND = "PulseGhostCameraSubject"

local function ghostCameraUsable()
    return ghostModel ~= nil and ghostModel.Parent ~= nil
        and ghostHumanoid ~= nil and ghostHumanoid.Parent ~= nil
        and ghostHumanoid.RootPart ~= nil and ghostHumanoid.Health > 0
end

local function enforceGhostCameraSubject()
    if deleted or not ghostCameraSaved then return end
    local camera = workspace.CurrentCamera
    if not camera or not ghostCameraUsable() then return end
    if camera.CameraSubject ~= ghostHumanoid then
        pcall(function() camera.CameraSubject = ghostHumanoid end)
    end
end

local function unbindGhostCamera()
    if GhostCam.bound then
        GhostCam.bound = false
        pcall(function() RunService:UnbindFromRenderStep(GHOST_CAMERA_BIND) end)
    end
    if GhostCam.changedConn then
        GhostCam.changedConn:Disconnect()
        GhostCam.changedConn, GhostCam.changedCamera = nil, nil
    end
end

local function bindGhostCamera(camera)
    if not GhostCam.bound then
        GhostCam.bound = true
        RunService:BindToRenderStep(GHOST_CAMERA_BIND, Enum.RenderPriority.Camera.Value - 1, enforceGhostCameraSubject)
    end
    if GhostCam.changedCamera ~= camera then
        if GhostCam.changedConn then GhostCam.changedConn:Disconnect() end
        GhostCam.changedCamera = camera
        GhostCam.changedConn = camera:GetPropertyChangedSignal("CameraSubject"):Connect(enforceGhostCameraSubject)
    end
end

local function restoreGhostCamera()
    unbindGhostCamera()
    if not ghostCameraSaved then return end
    ghostCameraSaved = false
    local camera = workspace.CurrentCamera
    local subject = ghostPreviousCameraSubject
    ghostPreviousCameraSubject = nil
    if camera then
        if not subject or not subject.Parent then subject = getHumanoid() end
        if subject then
            pcall(function() camera.CameraSubject = subject end)
        end
    end
end

local function saveAndSetGhostCamera()
    local camera = workspace.CurrentCamera
    if not camera or not ghostCameraUsable() then return false end

    if not ghostCameraSaved then
        local current = camera.CameraSubject
        -- never remember a ghost Humanoid as the "previous" subject
        if current and current ~= ghostHumanoid and current.Parent and current.Parent.Name:sub(-11) ~= "_PulseGhost" then
            ghostPreviousCameraSubject = current
        else
            ghostPreviousCameraSubject = getHumanoid()
        end
        ghostCameraSaved = true
    end

    bindGhostCamera(camera)

    if camera.CameraSubject ~= ghostHumanoid then
        local ok = pcall(function()
            camera.CameraSubject = ghostHumanoid
        end)
        if not ok then return false end
    end
    return camera.CameraSubject == ghostHumanoid
end

local function cloneCharacterSafely(char)
    local changed = {}
    local all = { char }
    for _, descendant in ipairs(char:GetDescendants()) do table.insert(all, descendant) end
    for _, inst in ipairs(all) do
        local ok, archivable = pcall(function() return inst.Archivable end)
        if ok and not archivable and pcall(function() inst.Archivable = true end) then changed[inst] = false end
    end
    local ok, clone = pcall(function() return char:Clone() end)
    for inst, oldValue in pairs(changed) do pcall(function() inst.Archivable = oldValue end) end
    if not ok then
        warn("[PulseRevolver] Full avatar clone failed: " .. tostring(clone))
        return nil
    end
    return clone
end

local function sourceTrackSpeed(track)
    local speed = 1
    pcall(function() if type(track.Speed) == "number" then speed = track.Speed end end)
    pcall(function() local value = track:GetSpeed() if type(value) == "number" then speed = value end end)
    return speed
end
local function sourceTrackWeight(track)
    local weight = 1
    pcall(function() weight = track.WeightTarget end)
    return weight
end

local function syncGhostAnimations(char, isMoving)
    if not ghostAnimator or not ghostModel then return false end
    local sourceHumanoid = char and char:FindFirstChildOfClass("Humanoid")
    local sourceAnimator = sourceHumanoid and sourceHumanoid:FindFirstChildOfClass("Animator")
    if not sourceAnimator then return false end
    local active = {}
    local syncMode = CONFIG.MODES.list[CONFIG.MODES.index]
    local noWalkAnim = syncMode ~= nil and syncMode.noWalkAnim == true -- idle keeps playing while the clone walks
    local sourceWalkId = Perf.walkId or ANIM.WALK:match("(%d+)$")
    local idleId = Perf.idleId or ANIM.IDLE:match("(%d+)$")
    local idle2Id = Perf.idle2Id or ANIM.IDLE2:match("(%d+)$")
    Perf.walkId, Perf.idleId, Perf.idle2Id = sourceWalkId, idleId, idle2Id
    for _, sourceTrack in ipairs(sourceAnimator:GetPlayingAnimationTracks()) do
        if sourceTrack.IsPlaying and sourceTrack.Animation then
            local id = animationIdOf(sourceTrack)
            if id == WATCHED_ANIMATION_ID or id == CONFIG.FLOW.animationId then
                local stale = ghostTrackMap[sourceTrack]
                if stale then
                    if stale.track then pcall(function() stale.track:Stop(0) end) end
                    if stale.animation and stale.animation.Parent then stale.animation:Destroy() end
                    ghostTrackMap[sourceTrack] = nil
                end
            elseif id == sourceWalkId then
                -- Real body's walk track is NOT mirrored. In the void its velocity-driven walk flickers
                -- on/off, which restarted/blended two out-of-phase walk cycles on the clone (stutter in
                -- place). The ghost's walk is owned solely by ghostWalkTrack below. (Any stale mirrored
                -- copy is cleaned up by the loop after this one, since it is not marked active.)
            else
                active[sourceTrack] = true
                local entry = ghostTrackMap[sourceTrack]
                if not entry or not entry.track or not entry.track.IsPlaying then
                    if entry then
                        if entry.track then pcall(function() entry.track:Stop(0) end) end
                        if entry.animation and entry.animation.Parent then entry.animation:Destroy() end
                        ghostTrackMap[sourceTrack] = nil
                    end
                    local animationCopy = sourceTrack.Animation:Clone()
                    animationCopy.Parent = ghostModel
                    local ok, cloneTrack = pcall(function() return ghostAnimator:LoadAnimation(animationCopy) end)
                    if ok and cloneTrack then
                        cloneTrack.Priority = sourceTrack.Priority
                        cloneTrack.Looped = sourceTrack.Looped
                        local speed = sourceTrackSpeed(sourceTrack)
                        local weight = math.max(sourceTrackWeight(sourceTrack), 0.001)
                        local mutedIdle = isMoving and not noWalkAnim and (id == idleId or id == idle2Id)
                        if mutedIdle then weight = 0.001 end
                        cloneTrack:Play(0, weight, speed)
                        pcall(function() cloneTrack.TimePosition = sourceTrack.TimePosition end)
                        entry = { track = cloneTrack, animation = animationCopy, weight = mutedIdle and 0 or nil, id = id }
                        ghostTrackMap[sourceTrack] = entry
                    else
                        animationCopy:Destroy()
                    end
                end
                if entry and entry.track and entry.track.IsPlaying then
                    local cloneTrack = entry.track
                    local sourceTime = sourceTrack.TimePosition
                    if math.abs(cloneTrack.TimePosition - sourceTime) > 0.09 then
                        pcall(function() cloneTrack.TimePosition = sourceTime end)
                    end
                    local speedNow = sourceTrackSpeed(sourceTrack)
                    if entry.speed ~= speedNow then entry.speed = speedNow cloneTrack:AdjustSpeed(speedNow) end
                    local weight = sourceTrackWeight(sourceTrack)
                    if id == idleId or id == idle2Id then weight = (isMoving and not noWalkAnim) and 0 or weight end
                    weight = math.max(weight, 0)
                    if entry.weight ~= weight then entry.weight = weight cloneTrack:AdjustWeight(weight, 0.06) end
                end
            end
        end
    end
    for sourceTrack, entry in pairs(ghostTrackMap) do
        if not active[sourceTrack] or not sourceTrack.IsPlaying then
            -- a standing clone keeps its idle through a short gap (< 0.25 s) in the real one instead of blinking
            local keep = false
            if not isMoving and (entry.id == idleId or entry.id == idle2Id) then
                entry.missingSince = entry.missingSince or os.clock()
                keep = os.clock() - entry.missingSince < 0.25
            end
            if not keep then
                if entry.track then pcall(function() entry.track:Stop(0.05) end) end
                if entry.animation and entry.animation.Parent then entry.animation:Destroy() end
                ghostTrackMap[sourceTrack] = nil
            end
        else
            entry.missingSince = nil
        end
    end
    if ghostWalkTrack then
        if isMoving and not noWalkAnim then
            if not ghostWalkTrack.IsPlaying or Perf.walkStopping then
                Perf.walkSpeed, Perf.walkStopping = nil, false
                ghostWalkTrack:Play(0.1, 1, 1)
            end
            local speed = math.clamp((ghostHumanoid and ghostHumanoid.WalkSpeed or 24) / CONFIG.WALK_REF_SPEED, 0.2, 24)
            if Perf.walkSpeed ~= speed then Perf.walkSpeed = speed ghostWalkTrack:AdjustSpeed(speed) end
        elseif ghostWalkTrack.IsPlaying and not Perf.walkStopping then
            -- stop once: re-calling Stop every sync tick kept restarting the fade-out
            Perf.walkSpeed, Perf.walkStopping = nil, true
            ghostWalkTrack:Stop(0.12)
        end
    end
    return true
end

-- EVERY frame: keep the clone's tracks locked to the real body's tracks.
-- The 20 Hz sync only corrected drift bigger than 0.09 s, so tracks the idle code drives by hand
-- (ping-pong reverse, holds, segment loops) were copied in visible steps = stutter. Tracks that are
-- standing still (speed 0) now follow the real track's time exactly, and speed changes are copied at once.
local function mirrorGhostTrackTimes()
    local now = os.clock()
    local frame = math.clamp(now - (Perf.mirrorAt or now), 1 / 120, 0.1)
    Perf.mirrorAt = now
    local tolerance = math.max(0.02, frame * 1.5) -- about one frame of drift is fine, more is corrected
    for sourceTrack, entry in pairs(ghostTrackMap) do
        local cloneTrack = entry.track
        if cloneTrack and cloneTrack.IsPlaying and sourceTrack.IsPlaying then
            local speedNow = sourceTrackSpeed(sourceTrack)
            if entry.speed ~= speedNow then
                entry.speed = speedNow
                cloneTrack:AdjustSpeed(speedNow)
            end
            local sourceTime = sourceTrack.TimePosition
            local drift = math.abs(cloneTrack.TimePosition - sourceTime)
            local length = cloneTrack.Length
            if length > 0 and drift > length / 2 then drift = length - drift end -- a looped track wrapped on one side only
            -- The idle code loops a short part of an animation by jumping the real track back (segment loops,
            -- ping-pong restarts). A jump smaller than the old 0.06 s tolerance was never copied, so the clone kept
            -- creeping forward past the end of the part (a slower loop that goes deeper into the animation).
            -- A backwards jump of the real track is now copied at once, whatever its size.
            local jumpedBack = entry.lastSourceTime ~= nil and speedNow > 0 and sourceTime < entry.lastSourceTime - 0.0005
            entry.lastSourceTime = sourceTime
            if speedNow == 0 then
                if drift > 0.002 then cloneTrack.TimePosition = sourceTime end
            elseif jumpedBack or drift > tolerance then
                cloneTrack.TimePosition = sourceTime
            end
        end
    end
end

local function getGhostMoveDirection()
    if UserInputService:GetFocusedTextBox() then return Vector3.zero end
    local camera = workspace.CurrentCamera
    if not camera then return Vector3.zero end
    local look, right = camera.CFrame.LookVector, camera.CFrame.RightVector
    local forward = Vector3.new(look.X, 0, look.Z)
    local rightFlat = Vector3.new(right.X, 0, right.Z)
    if forward.Magnitude < 0.001 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end
    if rightFlat.Magnitude < 0.001 then rightFlat = Vector3.new(1, 0, 0) else rightFlat = rightFlat.Unit end
    local direction = Vector3.zero
    if ghostMoveKeys[Enum.KeyCode.W] then direction += forward end
    if ghostMoveKeys[Enum.KeyCode.S] then direction -= forward end
    if ghostMoveKeys[Enum.KeyCode.D] then direction += rightFlat end
    if ghostMoveKeys[Enum.KeyCode.A] then direction -= rightFlat end
    if direction.Magnitude > 1 then direction = direction.Unit end
    return direction
end

syncGhostAnimations = Perf.wrap("ghostAnimSync", syncGhostAnimations)

local function updateGhostMovement()
    if not ghostHumanoid or not ghostHumanoid.Parent then return end
    local direction = getGhostMoveDirection()
    ghostHumanoid:Move(direction, false)
    Perf.ghostMoving = direction.Magnitude > 0.05 -- animStep follows this while the clone is shown
    mirrorGhostTrackTimes()
    local now = os.clock()
    if now - ghostAnimationSyncAt >= ghostAnimationSyncInterval then
        ghostAnimationSyncAt = now
        syncGhostAnimations(ghostSource, direction.Magnitude > 0.05)
    end
end

local function handoffGhostAnimationsToCharacter()
    local character = getCharacter()
    if not character or (ghostSource and ghostSource ~= character) then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local realAnimator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 1))
    if not realAnimator then return end
    -- Was the clone walking when we left it? (its own walk track is only "playing" while input is held)
    local ghostMoving = ghostWalkTrack ~= nil and ghostWalkTrack.IsPlaying and not Perf.walkStopping
    local idleId = Perf.idleId or ANIM.IDLE:match("(%d+)$")
    local idle2Id = Perf.idle2Id or ANIM.IDLE2:match("(%d+)$")
    local walkId = Perf.walkId or ANIM.WALK:match("(%d+)$")
    local ownTracks = {}
    for _, t in pairs(trk) do ownTracks[t] = true end
    local function handoffTrack(cloneTrack, animationSource)
        if not cloneTrack or not cloneTrack.IsPlaying or not cloneTrack.Animation then return end
        local animationId = animationIdOf(cloneTrack)
        if not animationId or animationId == WATCHED_ANIMATION_ID or animationId == CONFIG.FLOW.animationId then return end
        if ghostMoving and (animationId == idleId or animationId == idle2Id) then
            -- the clone's idle is muted while it walks; do NOT copy that ~0 weight onto the real idle,
            -- and keep the real idle off so the walk we hand over is the only pose
            for _, idleTrack in ipairs({ trk.idle, trk.idle2 }) do
                if idleTrack then
                    want[idleTrack] = false
                    if idleTrack.IsPlaying then idleTrack:Stop(0.1) end
                end
            end
            return
        end
        local realTrack = nil
        for _, candidate in ipairs(realAnimator:GetPlayingAnimationTracks()) do
            if candidate.IsPlaying and animationIdOf(candidate) == animationId then realTrack = candidate break end
        end
        if not realTrack then
            for _, candidate in pairs(trk) do
                if candidate and animationIdOf(candidate) == animationId then realTrack = candidate break end
            end
        end
        local speed, weight = sourceTrackSpeed(cloneTrack), math.max(sourceTrackWeight(cloneTrack), 0.001)
        -- our own tracks always run at full weight; the clone's weight may be mid-fade
        if realTrack and ownTracks[realTrack] then weight = 1 end
        if ghostMoving and animationId == walkId then
            -- keep the handed-over walk alive (and at the clone's speed) until the real body is really moving
            Perf.handoffMove = { untilT = os.clock() + 0.35, speed = math.clamp(speed, 0.2, 3) }
        end
        if realTrack and ownTracks[realTrack] and realTrack.IsPlaying and animationId ~= walkId then
            -- our own real track kept running the whole time (the clone only mirrors it, slightly behind), so
            -- copying the clone's time / speed / weight back would only make the pose jump: leave it alone
            return
        end
        if realTrack then
            pcall(function()
                if not realTrack.IsPlaying then realTrack:Play(0.12, weight, speed) end
                realTrack.TimePosition = cloneTrack.TimePosition
                realTrack:AdjustSpeed(speed)
                realTrack:AdjustWeight(weight, 0.10)
            end)
            if ours[realTrack] then
                want[realTrack], wantSpeed[realTrack], lastTime[realTrack] = true, speed, cloneTrack.TimePosition
            else
                ours[realTrack] = true
                ghostHandoffTracks[realTrack] = os.clock() + 0.45
                realTrack.Stopped:Connect(function() ours[realTrack] = nil ghostHandoffTracks[realTrack] = nil end)
            end
            return
        end
        local animationCopy = animationSource and animationSource:Clone()
        if not animationCopy then
            animationCopy = Instance.new("Animation")
            animationCopy.AnimationId = cloneTrack.Animation.AnimationId
        end
        animationCopy.Name = "PulseGhostHandoffAnimation"
        animationCopy.Parent = character
        local ok, loadedTrack = pcall(function() return realAnimator:LoadAnimation(animationCopy) end)
        if not ok or not loadedTrack then animationCopy:Destroy() return end
        loadedTrack.Priority = cloneTrack.Priority
        loadedTrack.Looped = cloneTrack.Looped
        ours[loadedTrack] = true
        ghostHandoffTracks[loadedTrack] = os.clock() + 0.45
        loadedTrack:Play(0.12, weight, speed)
        pcall(function() loadedTrack.TimePosition = cloneTrack.TimePosition end)
        loadedTrack:AdjustSpeed(speed)
        loadedTrack.Stopped:Connect(function()
            ours[loadedTrack] = nil
            ghostHandoffTracks[loadedTrack] = nil
            if animationCopy.Parent then animationCopy:Destroy() end
        end)
    end
    for _, entry in pairs(ghostTrackMap) do
        if entry and entry.track then handoffTrack(entry.track, entry.animation) end
    end
    if ghostWalkTrack then handoffTrack(ghostWalkTrack, ghostWalkTrack.Animation) end
end

-- ONE revolver only: while the ghost exists the live revolver is carried by the ghost's
-- arm (instead of the clone getting a second frozen copy); it goes back on destroy.
local function returnRevolverToCharacter()
    if not Perf.revolverOnGhost then return end
    Perf.revolverOnGhost = false
    if not model or not root then return end
    local char = player.Character
    local arm = char and char:FindFirstChild("Right Arm")
    local grip = root:FindFirstChild("PulseRevolverGrip")
    if arm and grip and model.Parent ~= nil then
        pcall(function()
            grip.Part0 = arm
            model.Parent = char
        end)
    else
        -- character is gone (respawn); attach() rebuilds a fresh revolver
        pcall(function() model.Parent = nil end)
    end
end

local function destroyGhost(preserveAnimations)
    if preserveAnimations then handoffGhostAnimationsToCharacter() end
    setRealBodyHidden(getCharacter(), false)
    returnRevolverToCharacter()
    restoreGhostCamera()
    for sourceTrack, entry in pairs(ghostTrackMap) do
        if entry.track then pcall(function() entry.track:Stop(0) end) end
        if entry.animation and entry.animation.Parent then entry.animation:Destroy() end
        ghostTrackMap[sourceTrack] = nil
    end
    if ghostWalkTrack then pcall(function() ghostWalkTrack:Stop(0) end) ghostWalkTrack = nil end
    Perf.walkSpeed, Perf.walkStopping = nil, false
    if ghostModel then ghostModel:Destroy() ghostModel = nil end
    Perf.ghostMoving = false
    ghostSource, ghostHumanoid, ghostRoot, ghostHead = nil, nil, nil, nil
    ghostNeutralHeadOffset, ghostAnimator = nil, nil
    ghostBuildRetryAt, ghostExpectedCFrame, ghostAnimationSyncAt = 0, nil, 0
    ghostFolder:ClearAllChildren()
end

local function buildGhost(char, spawnCFrame)
    if ghostBuildInProgress then return false end
    if not char or char ~= player.Character then
        ghostLastBuildError = "source character is not the current Player.Character"
        return false
    end
    ghostBuildInProgress = true
    destroyGhost()
    local clone = nil
    local ok, err = xpcall(function()
        local sourceHumanoid = char:FindFirstChildOfClass("Humanoid")
        local sourceRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        if not sourceHumanoid or not sourceRoot then error("source Humanoid or root part missing") end
        clone = cloneCharacterSafely(char)
        if not clone then error("Character:Clone() returned nil") end
        local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
        local cloneRoot = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("Torso")
        local cloneHead = clone:FindFirstChild("Head")
        if not cloneHumanoid or not cloneRoot or not cloneHead then error("cloned avatar missing Humanoid/root/Head") end
        clone.Name = char.Name .. "_PulseGhost"
        clone.PrimaryPart = cloneRoot
        local oldAnimator = cloneHumanoid:FindFirstChildOfClass("Animator")
        if oldAnimator then oldAnimator:Destroy() end
        local cloneAnimator = Instance.new("Animator")
        cloneAnimator.Parent = cloneHumanoid
        cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        cloneHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        cloneHumanoid.NameDisplayDistance = 0
        cloneHumanoid.HealthDisplayDistance = 0
        cloneHumanoid.AutoRotate = true
        cloneHumanoid.PlatformStand = false
        cloneHumanoid.Sit = false
        cloneHumanoid.WalkSpeed = 24
        cloneHumanoid.UseJumpPower = sourceHumanoid.UseJumpPower
        cloneHumanoid.JumpPower = sourceHumanoid.JumpPower
        cloneHumanoid.JumpHeight = sourceHumanoid.JumpHeight
        cloneHumanoid.HipHeight = sourceHumanoid.HipHeight
        cloneHumanoid.BreakJointsOnDeath = false
        -- One pass over descendants replaces the old two separate full passes.
        -- The ghost is a local visual stand-in only. Game systems must not adopt it
        -- (CollectionService tags) and it should not carry the real avatar's effects.
        local CollectionService = game:GetService("CollectionService")
        for _, tag in ipairs(CollectionService:GetTags(clone)) do CollectionService:RemoveTag(clone, tag) end
        for _, stateType in ipairs({
            Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Seated,
            Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
            Enum.HumanoidStateType.PlatformStanding, Enum.HumanoidStateType.Flying,
        }) do pcall(function() cloneHumanoid:SetStateEnabled(stateType, false) end) end
        local revolverClone = clone:FindFirstChild("Pulse Revolver")
        if revolverClone then revolverClone:Destroy() end
        local descendants = clone:GetDescendants()
        for _, descendant in ipairs(descendants) do
            for _, tag in ipairs(CollectionService:GetTags(descendant)) do CollectionService:RemoveTag(descendant, tag) end
            if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
                descendant:Destroy()
            elseif (descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam")
                or descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles")
                or descendant:IsA("Light") or descendant:IsA("Sound") or descendant:IsA("Highlight")
                or descendant:IsA("ForceField") or descendant:IsA("BillboardGui")) then
                descendant:Destroy()
            elseif descendant:IsA("BasePart") then
                descendant.Anchored = false
                descendant.CanTouch = false
                descendant.CanQuery = false
                if descendant == cloneRoot then descendant.CanCollide = false end
            end
        end
        clone.Parent = (Perf.stage and Perf.stage.camParent and workspace.CurrentCamera) or workspace
        local desiredRoot = spawnCFrame or sourceRoot.CFrame
        local pivotToRoot = clone:GetPivot():ToObjectSpace(cloneRoot.CFrame)
        clone:PivotTo(desiredRoot * pivotToRoot:Inverse())
        ghostExpectedCFrame = desiredRoot
        ghostModel, ghostSource = clone, char
        ghostHumanoid, ghostRoot, ghostHead = cloneHumanoid, cloneRoot, cloneHead
        ghostNeutralHeadOffset = cloneRoot.CFrame:PointToObjectSpace(cloneHead.Position)
        ghostAnimator = cloneAnimator
        ghostTrackMap = {}
        ghostAnimationSyncAt = 0
        local walkAnimation = Instance.new("Animation")
        walkAnimation.Name = "PulseGhostWalk"
        walkAnimation.AnimationId = ANIM.WALK
        walkAnimation.Parent = clone
        local okWalk, walkTrack = pcall(function() return cloneAnimator:LoadAnimation(walkAnimation) end)
        if okWalk and walkTrack then
            walkTrack.Priority = Enum.AnimationPriority.Action
            walkTrack.Looped = true
            ghostWalkTrack = walkTrack
        else
            walkAnimation:Destroy()
            ghostWalkTrack = nil
        end
        do
            local ghostArm = clone:FindFirstChild("Right Arm")
            local grip = root and model and root:FindFirstChild("PulseRevolverGrip")
            if ghostArm and grip and model.Parent == char and Perf.on("revolver") then
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d.LocalTransparencyModifier = 0
                        realBodyTransparency[d] = nil
                    end
                end
                grip.Part0 = ghostArm
                model.Parent = clone
                Perf.revolverOnGhost = true
            end
        end
        do
            local waitUntil = os.clock() + 1
            while clone.Parent and not cloneHumanoid.RootPart and os.clock() < waitUntil do task.wait() end
        end
        if Perf.on("camera") and not saveAndSetGhostCamera() then warn("[PulseRevolver] Ghost created, but camera could not be switched") end
    end, debug.traceback)
    ghostBuildInProgress = false
    if not ok then
        ghostLastBuildError = tostring(err)
        warn("[PulseRevolver] FULL AVATAR GHOST BUILD FAILED:\n" .. ghostLastBuildError)
        if ghostCameraSaved then restoreGhostCamera() end
        if clone then pcall(function() clone:Destroy() end) end
        ghostModel, ghostSource, ghostHumanoid, ghostRoot, ghostHead = nil, nil, nil, nil, nil
        ghostNeutralHeadOffset, ghostAnimator, ghostWalkTrack = nil, nil, nil
        ghostTrackMap = {}
        return false
    end
    ghostLastBuildError = nil
    ghostBuildRetryAt = 0
    return true
end

local function pivotGhostRootTo(desiredRootCFrame)
    if not ghostModel or not ghostModel.Parent or not ghostRoot or not ghostRoot.Parent then return false end
    local ok = pcall(function()
        local pivotToRoot = ghostModel:GetPivot():ToObjectSpace(ghostRoot.CFrame)
        ghostModel:PivotTo(desiredRootCFrame * pivotToRoot:Inverse())
    end)
    if not ok then return false end
    ghostExpectedCFrame = desiredRootCFrame
    return true
end

-- Teleports the real body onto the clone. The clone is still moving when we leave it, so the real body keeps
-- the clone's velocity: zeroing it stopped us dead and the clone's last frame of travel looked like a pull back.
local function landOnGhost(hrp, destination)
    if not hrp or not hrp.Parent or not destination then return end
    local char = hrp.Parent

    -- 1) only the sideways speed is carried over. The up / down part is dropped: carrying it (or gravity that
    --    built up while the real body was parked) pushed the character down into the floor after the teleport.
    local velocity = Vector3.zero
    if ghostRoot and ghostRoot.Parent then
        local okVelocity, value = pcall(function() return ghostRoot.AssemblyLinearVelocity end)
        if okVelocity and value then velocity = Vector3.new(value.X, 0, value.Z) end
    end

    -- 2) never land below the floor: if the spot is lower than a standing character's root should be above the
    --    ground under it, lift it up to the standing height (at most 4 studs, so odd geometry cannot fling us)
    pcall(function()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local standHeight = hum.HipHeight + hrp.Size.Y / 2
        if hum.RigType == Enum.HumanoidRigType.R6 then
            local leg = char:FindFirstChild("Left Leg") or char:FindFirstChild("Right Leg")
            standHeight += leg and leg.Size.Y or 2
        end
        local ignore = { char, workspace.CurrentCamera, ghostModel, ghostFolder, workspace:FindFirstChild("Live") }
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then table.insert(ignore, plr.Character) end
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore
        params.RespectCanCollide = true
        local origin = destination.Position + Vector3.new(0, 3, 0)
        local hit = workspace:Raycast(origin, Vector3.new(0, -16, 0), params)
        if hit then
            local lift = (hit.Position.Y + standHeight) - destination.Position.Y
            if lift > 0.15 and lift <= 4 then
                destination = destination + Vector3.new(0, lift, 0)
            end
        end
    end)

    hrp.CFrame = destination
    hrp.AssemblyLinearVelocity = velocity
    hrp.AssemblyAngularVelocity = Vector3.zero
end

------------------------------------------------------------------
-- ANIMATION VOID TRIP
------------------------------------------------------------------
endAnimationVoidTrip = function(reason)
    local trip = animationVoidTrip
    if not trip then return end
    CONFIG.HIDE.restoreAll() -- teleporting back: hidden targets are visible again
    animationVoidTrip = nil
    if voidReferenceConnection then voidReferenceConnection:Disconnect() voidReferenceConnection = nil end
    orbitEnabled = false
    orbitWorldCF, lastWorldCF = nil, nil
    local hrp = trip.hrp
    if hrp and hrp.Parent and trip.character == player.Character then
        -- stop the watched animation first so it is not playing when we land on the clone
        CONFIG.FAILSAFE.cancelWatchedAnimation(trip.track, trip.target)
        if engaged and engagedChar == trip.character then
            release(true)
        else
            setHidden(hrp, "PhysicsRepRootPart", hrp)
            local hum = trip.humanoid
            if hum and hum.Parent then
                hum.AutoRotate = true
                setHidden(hum, "PlatformStand", false)
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end
        local cloneExit = ghostRoot and ghostRoot.Parent and ghostRoot.CFrame
            or (ghostModel and ghostModel.Parent and ghostModel:GetPivot()) or trip.ghostCFrame
        if cloneExit then
            landOnGhost(hrp, cloneExit)
        else
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        local exclusion = trip.character:FindFirstChild("MovingExclusion")
        if exclusion then exclusion:Destroy() end
    end
    engaged, engagedChar = false, nil
    shotTargetModel, shotReturnCFrame, ghostWorldCF = nil, nil, nil
    if CONFIG.FLOW.active then -- R (Bring Mode Kill / Banish) finished through the void trip
        CONFIG.FLOW.destination = nil
        CONFIG.FLOW.active = false
        CONFIG.FLOW.fired = false
        CONFIG.FLOW.toolWarned = false
        CONFIG.FLOW.toolName = ORBIT_TOOL_NAME
    end
    diagnosticStatus = reason or "Animation void test ended"
    diagnosticLastOutcome = diagnosticStatus
    setOrbitStatus("disabled")
    AV.setEnabled(false)
    AV.apply(nil)
end

beginAnimationVoidTrip = function(track, target, targetHumanoid)
    if animationVoidTrip or not (orbitEnabled and AV.enabled) then return end
    if not track or not track.IsPlaying then return end
    if not isValidShotTarget(target) or not targetHumanoid or targetHumanoid.Health <= 0 then
        diagnosticStatus = "Animation detected, but target is not alive / available"
        return
    end
    local character, hrp, humanoid = getCharacter(), getRoot(), getHumanoid()
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not (character and hrp and humanoid and targetRoot and targetRoot:IsA("BasePart")) then
        diagnosticStatus = "Cannot start void test: character or target root unavailable"
        return
    end
    local returnCFrame = shotReturnCFrame or hrp.CFrame
    local orbitWorld = orbitWorldCF or hrp.CFrame
    local orbitPosition = orbitWorld.Position
    -- R (Bring Mode) and E (Attack Mode) each pick their own void height
    local voidY = CONFIG.FLOW.active and CONFIG.BRING.voidY() or CONFIG.ATTACK.voidY()
    local voidWorldCFrame = CFrame.new(orbitPosition.X, voidY, orbitPosition.Z) * (orbitWorld - orbitPosition)
    local trip = {
        track = track, target = target, targetHumanoid = targetHumanoid, targetRoot = targetRoot,
        character = character, hrp = hrp, humanoid = humanoid, returnCFrame = returnCFrame,
        voidWorldCFrame = voidWorldCFrame, ghostCFrame = ghostWorldCF or returnCFrame, startedAt = os.clock(),
    }
    animationVoidTrip = trip
    orbitEnabled = false
    orbitWorldCF, lastWorldCF = nil, nil
    setOrbitStatus("Orbit paused; preparing target-relative void handoff")
    humanoid.AutoRotate = false
    setHidden(humanoid, "PlatformStand", true)
    AV.installHook()
    AV.setEnabled(true)
    AV.apply(AV.BIGGEST)
    task.spawn(function()
        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()
        if animationVoidTrip ~= trip then return end
        if trip.character ~= player.Character or not hrp.Parent then
            endAnimationVoidTrip("Local character changed / root removed")
            return
        end
        if not targetRoot.Parent or not targetRoot:IsDescendantOf(workspace) then
            endAnimationVoidTrip("Target root removed during void handoff")
            return
        end
        local lastVoidRelativeCFrame = nil
        local function applyVoidPosition()
            local desiredRelative = targetRoot.CFrame:ToObjectSpace(voidWorldCFrame)
            local changed = lastVoidRelativeCFrame == nil
            if lastVoidRelativeCFrame then
                changed = (desiredRelative.Position - lastVoidRelativeCFrame.Position).Magnitude > 0.001
                    or (desiredRelative.LookVector - lastVoidRelativeCFrame.LookVector).Magnitude > 0.001
                    or (desiredRelative.UpVector - lastVoidRelativeCFrame.UpVector).Magnitude > 0.001
            end
            if changed then hrp.CFrame = desiredRelative lastVoidRelativeCFrame = desiredRelative end
            if hrp.AssemblyLinearVelocity.Magnitude > 0.01 then hrp.AssemblyLinearVelocity = Vector3.zero end
            if hrp.AssemblyAngularVelocity.Magnitude > 0.01 then hrp.AssemblyAngularVelocity = Vector3.zero end
        end
        applyVoidPosition()
        setHidden(hrp, "PhysicsRepRootPart", targetRoot)
        local accumulator = 0
        voidReferenceConnection = RunService.Heartbeat:Connect(function(dt)
            if animationVoidTrip ~= trip then
                if voidReferenceConnection then voidReferenceConnection:Disconnect() voidReferenceConnection = nil end
                return
            end
            if trip.character ~= player.Character or not hrp.Parent then
                endAnimationVoidTrip("Local character changed / root removed")
                return
            end
            if not targetRoot.Parent or not targetRoot:IsDescendantOf(workspace) then
                endAnimationVoidTrip("Target root removed during void test")
                return
            end
            accumulator += dt
            if accumulator < (1 / 30) then return end
            accumulator %= (1 / 30)
            applyVoidPosition()
        end)
        diagnosticStatus = string.format("Orbit-relative void position active at Y=%s", tostring(voidY))
        setOrbitStatus("void positioning through target reference")
    end)
end

CONFIG.FLOW.finish = function(reason)
    if not CONFIG.FLOW.active then return end
    CONFIG.HIDE.restoreAll() -- teleporting back: hidden targets are visible again
    local char = getCharacter()
    local hrp = getRoot()
    local hum = getHumanoid()

    -- Match move 1's handoff: return to the live ghost root, not the bullet's
    -- raycast endpoint. The old endpoint could be thousands of studs above the
    -- map when the barrel was aimed upward, which caused the sky teleport.
    -- Keep the firing CFrame as a fallback in case the clone was already removed.
    local destination = nil
    if ghostRoot and ghostRoot.Parent then
        destination = ghostRoot.CFrame
    elseif ghostModel and ghostModel.Parent then
        local cloneRoot = ghostModel:FindFirstChild("HumanoidRootPart") or ghostModel:FindFirstChild("Torso")
        destination = cloneRoot and cloneRoot.CFrame or ghostModel:GetPivot()
    end
    destination = destination or CONFIG.FLOW.destination or shotReturnCFrame

    -- like move 1: stop the watched animation first so it is not playing when we land on the clone
    CONFIG.FAILSAFE.cancelWatchedAnimation(diagnosticTrack, shotTargetModel)

    orbitEnabled = false
    orbitWorldCF, lastWorldCF = nil, nil
    if engaged and engagedChar == char then
        release(true)
    else
        if hrp and hrp.Parent then setHidden(hrp, "PhysicsRepRootPart", hrp) end
        if hum and hum.Parent then
            hum.AutoRotate = true
            if hum.PlatformStand then setHidden(hum, "PlatformStand", false) end
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end

    if hrp and hrp.Parent and destination then landOnGhost(hrp, destination) end
    -- and once more right after landing on the clone, in case it started playing again
    CONFIG.FAILSAFE.cancelWatchedAnimation(diagnosticTrack, shotTargetModel)

    if char then
        local exclusion = char:FindFirstChild("MovingExclusion")
        if exclusion then exclusion:Destroy() end
    end

    engaged, engagedChar = false, nil
    shotTargetModel, shotReturnCFrame, ghostWorldCF = nil, nil, nil
    CONFIG.FLOW.destination = nil
    CONFIG.FLOW.active = false
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = ORBIT_TOOL_NAME
    diagnosticStatus = reason or "Flowing Water return completed"
    diagnosticLastOutcome = diagnosticStatus
    setOrbitStatus("disabled")
    AV.setEnabled(false)
    AV.apply(nil)
end

------------------------------------------------------------------
-- FAILSAFE: cancel watched animation / return to clone
------------------------------------------------------------------
-- Stops the watched move animation (locally) on our animator, the target's animator and
-- the given track. Only called right before we teleport to the clone.
function CONFIG.FAILSAFE.cancelWatchedAnimation(trackHint, targetModel)
    local function stopIfWatched(track)
        local id = track and animationIdOf(track)
        if track and (id == WATCHED_ANIMATION_ID or id == CONFIG.FLOW.animationId) then
            pcall(function() track:Stop(0) end)
        end
    end
    local function stopAllWatchedOn(model)
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator then return end
        local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
        if ok then for _, track in ipairs(tracks) do stopIfWatched(track) end end
    end
    stopIfWatched(trackHint)
    stopAllWatchedOn(getCharacter())
    stopAllWatchedOn(targetModel)
end

-- Orbit/void positioning never saw the watched animation: stop it all and go back to the clone.
CONFIG.FAILSAFE.returnToClone = function(reason)
    CONFIG.HIDE.restoreAll() -- teleporting back: hidden targets are visible again
    local char, hrp, hum = getCharacter(), getRoot(), getHumanoid()
    local destination = nil
    if ghostRoot and ghostRoot.Parent then
        destination = ghostRoot.CFrame
    elseif ghostModel and ghostModel.Parent then
        destination = ghostModel:GetPivot()
    end
    destination = destination or ghostWorldCF or shotReturnCFrame

    CONFIG.FAILSAFE.cancelWatchedAnimation(nil, shotTargetModel)
    disconnectDiagnosticConnections()
    diagnosticTrack, diagnosticTarget, diagnosticTargetHumanoid = nil, nil, nil

    orbitEnabled = false
    orbitWorldCF, lastWorldCF = nil, nil
    if engaged and engagedChar == char then
        release(true)
    else
        if hrp and hrp.Parent then setHidden(hrp, "PhysicsRepRootPart", hrp) end
        if hum and hum.Parent then
            hum.AutoRotate = true
            if hum.PlatformStand then setHidden(hum, "PlatformStand", false) end
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end
    if hrp and hrp.Parent and destination then landOnGhost(hrp, destination) end
    if char then
        local exclusion = char:FindFirstChild("MovingExclusion")
        if exclusion then exclusion:Destroy() end
    end

    engaged, engagedChar = false, nil
    shotTargetModel, shotReturnCFrame, ghostWorldCF = nil, nil, nil
    CONFIG.FLOW.destination = nil
    CONFIG.FLOW.active = false
    CONFIG.FLOW.fired = false
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = ORBIT_TOOL_NAME
    diagnosticStatus = reason or "Failsafe return completed"
    diagnosticLastOutcome = diagnosticStatus
    setOrbitStatus("disabled")
    AV.setEnabled(false)
    AV.apply(nil)
end

------------------------------------------------------------------
-- ORBIT HEARTBEAT (30 HZ; VOID TRIP OWNS ITS OWN WRITER)
------------------------------------------------------------------
local function orbitStep(dt)
    if deleted then return end
    if animationVoidTrip then setOrbitStatus("paused (target-relative void position)") return end
    orbitAccumulator += dt
    -- Fling sweeps the distance several times per second, so it runs every frame instead of 30 Hz
    local fastOrbit = CONFIG.FLING.active
    if not fastOrbit and orbitAccumulator < ORBIT_UPDATE_INTERVAL then return end
    orbitAccumulator = fastOrbit and 0 or (orbitAccumulator % ORBIT_UPDATE_INTERVAL)
    if not orbitEnabled then
        GhostCam.gateStart = nil
        if CONFIG.FLING.active then CONFIG.FLING.reset() end
        release(false) setOrbitStatus("disabled") return
    end
    local target = resolveOrbitTarget()
    local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
    if not targetHumanoid or not targetRoot then
        if CONFIG.FLOW.active and CONFIG.FLOW.finish then
            CONFIG.FLOW.finish("Flowing Water target lost")
        elseif CONFIG.FLING.active then
            CONFIG.FLING.finish("Fling target lost")
        else
            release(false)
            setOrbitStatus("waiting for target")
        end
        return
    end
    local targetTorso = target:FindFirstChild("Torso")
    if targetHumanoid.Health <= 0 or (targetTorso and targetTorso.Transparency == 1) then
        if CONFIG.FLOW.active and CONFIG.FLOW.finish then
            CONFIG.FLOW.finish("Flowing Water target died / became hidden")
        elseif CONFIG.FLING.active then
            CONFIG.FLING.finish("Fling target died / became hidden")
        else
            release(false)
            setOrbitStatus("target dead / hidden - paused")
        end
        return
    end
    local myCharacter, myRoot, myHumanoid = getCharacter(), getRoot(), getHumanoid()
    if not myCharacter or not myRoot or not myHumanoid then release(false) setOrbitStatus("waiting for local character") return end
    if engaged and engagedChar ~= myCharacter then engaged, engagedChar = false, nil end
    if not sethidden and not engaged then setOrbitStatus("needs sethiddenproperty") return end
    if not engaged then
        -- hold the real body in place until the camera is on the clone (1.5s safety timeout)
        local cam = workspace.CurrentCamera
        if not (cam and ghostModel and ghostHumanoid and cam.CameraSubject == ghostHumanoid) then
            GhostCam.gateStart = GhostCam.gateStart or os.clock()
            if os.clock() - GhostCam.gateStart < 1.5 then
                setOrbitStatus("waiting for camera on clone")
                return
            end
        end
        GhostCam.gateStart = nil
        engaged, engagedChar = true, myCharacter
        myHumanoid.AutoRotate = false
        lastSpace = 0
        local toolName = CONFIG.FLOW.toolName or ORBIT_TOOL_NAME
        local tool = myCharacter:FindFirstChild(toolName)
        if not tool then
            local backpack = player:FindFirstChildOfClass("Backpack")
            tool = backpack and backpack:FindFirstChild(toolName)
        end
        if tool and tool:IsA("Tool") then
            equipToolBriefly(myCharacter, myHumanoid, tool, CONFIG.FLOW.active and "flowing" or "primary")
        elseif CONFIG.FLOW.active and not CONFIG.FLOW.toolWarned then
            CONFIG.FLOW.toolWarned = true
            warn("[PulseRevolver] Tool named 'Flowing Water' was not found in Character or Backpack")
        end
    end
    setHidden(myHumanoid, "PlatformStand", true)
    myRoot.AssemblyLinearVelocity = Vector3.zero
    myRoot.AssemblyAngularVelocity = Vector3.zero
    if not myCharacter:FindFirstChild("MovingExclusion") then
        local folder = Instance.new("Folder")
        folder.Name = "MovingExclusion"
        folder.Parent = myCharacter
    end
    local distance = ORBIT_DISTANCE
    local fling = CONFIG.FLING
    if fling.active then
        fling.sweepStart = fling.sweepStart or os.clock()
        local elapsed = os.clock() - fling.sweepStart
        if elapsed >= fling.LAPS * fling.LAP_TIME then
            fling.finish("Fling complete (" .. fling.LAPS .. " laps)")
            return
        end
        distance = fling.distanceAt(elapsed)
    end
    local forwardOffset, upOffset = distance, ORBIT_HEIGHT
    if fling.active and fling.USE_Y_POS then
        -- same sweep values, but applied up/down instead of front/back
        forwardOffset, upOffset = fling.Y_FORWARD, ORBIT_HEIGHT + distance
    end
    local behindCF = offsetBehind(targetRoot, upOffset, forwardOffset)
    orbitWorldCF, lastWorldCF = behindCF, behindCF
    -- Fling: spin our character in place (random direction) while the sweep runs
    local writeCF = fling.active and (behindCF * fling.stepRotation(dt)) or behindCF
    if ORBIT_OFFSET_SPACE == "World" then myRoot.CFrame = writeCF - targetRoot.Position
    else myRoot.CFrame = targetRoot.CFrame:ToObjectSpace(writeCF) end
    setHidden(myRoot, "PhysicsRepRootPart", targetRoot)
    local now = os.clock()
    if now - lastSpace >= 2 then
        lastSpace = now
        if not myCharacter:GetAttribute("HoldingSpace") then
            local communicate = myCharacter:FindFirstChild("Communicate")
            if communicate then
                pcall(communicate.FireServer, communicate, {
                    Goal = "KeyPress", Key = Enum.KeyCode.Space,
                    MousePos = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
                })
            end
        end
    end
    local info = string.format("%.1f behind, %.1f up (%s)", distance, ORBIT_HEIGHT, ORBIT_OFFSET_SPACE)
    if info ~= lastInfo then lastInfo = info end
    setOrbitStatus("orbiting target")
end

orbitConnection = RunService.Heartbeat:Connect(Perf.wrap("orbitStep", orbitStep))
diagnosticConnection = RunService.Heartbeat:Connect(Perf.wrap("diagnostics", updateDiagnostics))
characterConnection2 = player.CharacterAdded:Connect(function()
    resetToolCooldown()
    finishDiagnosticWatch("Local character respawned; monitor reset")
    engaged, engagedChar = false, nil
    orbitWorldCF, lastWorldCF = nil, nil
    shotTargetModel, shotReturnCFrame, ghostWorldCF = nil, nil, nil
    CONFIG.FLING.reset()
end)

-- No camera render-step: Roblox follows CameraSubject normally.

ghostRenderConnection = RunService.RenderStepped:Connect(Perf.wrap("ghostRender", function()
    if deleted then return end
    Perf.ghostAlive, Perf.orbitOn = ghostModel ~= nil, orbitEnabled
    local char = getCharacter()
    local shouldShow = orbitEnabled or animationVoidTrip ~= nil or Perf.testGhost == true
    local spawnCFrame
    if animationVoidTrip then spawnCFrame = animationVoidTrip.ghostCFrame or ghostWorldCF or shotReturnCFrame
    elseif orbitEnabled then spawnCFrame = ghostWorldCF or shotReturnCFrame
    elseif Perf.testGhost then spawnCFrame = getRoot() and (getRoot().CFrame * CFrame.new(0, 0, -8)) or nil end
    if not shouldShow or not char or not getRoot() then
        if realBodyHidden then setRealBodyHidden(char, false) end
        if ghostModel or ghostCameraSaved then destroyGhost(true) end
        return
    end
    if ghostModel and (ghostSource ~= char or not ghostModel.Parent or not ghostRoot or not ghostRoot.Parent) then destroyGhost() end
    if not ghostModel and not ghostBuildInProgress and os.clock() >= ghostBuildRetryAt then
        local built = buildGhost(char, spawnCFrame)
        if not built then
            ghostBuildRetryAt = os.clock() + 1
            setRealBodyHidden(char, false)
            return
        end
    end
    if not ghostModel then return end
    local camOn = Perf.on("camera")
    local cameraReady = camOn and saveAndSetGhostCamera()
    if Perf.on("hide") then setRealBodyHidden(char, (not camOn) or cameraReady) end
    if Perf.on("sync") then updateGhostMovement() end
end))

------------------------------------------------------------------
-- SHOT TARGET / ORBIT TRIGGER
------------------------------------------------------------------
local function triggerOrbitSequence(targetModel, firingCFrame)
    if not isValidShotTarget(targetModel) or animationVoidTrip or CONFIG.FLOW.active then return end
    CONFIG.FLOW.destination = nil
    CONFIG.FLOW.active = false
    CONFIG.FLOW.fired = false
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = ORBIT_TOOL_NAME
    local shotCFrame = firingCFrame or (getRoot() and getRoot().CFrame)
    if shotTargetModel ~= targetModel or not orbitEnabled then
        disconnectDiagnosticConnections()
        if shotTargetModel ~= targetModel then diagnosticTrack, diagnosticTarget, diagnosticTargetHumanoid = nil, nil, nil end
        shotReturnCFrame = shotCFrame
    end
    ghostWorldCF = shotCFrame or shotReturnCFrame
    if ghostModel and ghostWorldCF then pivotGhostRootTo(ghostWorldCF) end
    shotTargetModel = targetModel
    -- Ghost + camera first, THEN orbit: the real body must not move to the target
    -- until the camera is already following the clone.
    if not ghostModel then
        local char = getCharacter()
        if char and buildGhost(char, ghostWorldCF or shotReturnCFrame) then
            local cameraReady = saveAndSetGhostCamera()
            setRealBodyHidden(char, cameraReady)
        else
            ghostBuildRetryAt = os.clock() + 0.25
        end
    elseif ghostWorldCF then
        pivotGhostRootTo(ghostWorldCF)
        saveAndSetGhostCamera()
    end
    orbitEnabled = true
    AV.setEnabled(true)
    diagnosticLastHandledTrack = nil
    diagnosticStatus = "Armed; waiting for animation " .. WATCHED_ANIMATION_ID .. " or " .. CONFIG.FLOW.animationId
    diagnosticLastOutcome = "Armed: Orbit + Anti Void enabled; waiting for animation"
    CONFIG.FAILSAFE.deadline = os.clock() + CONFIG.FAILSAFE.TIMEOUT
end

------------------------------------------------------------------
-- ANIMATION SYSTEM
------------------------------------------------------------------
local function clearAnimations()
    animReady = false
    for handoffTrack in pairs(ghostHandoffTracks) do
        pcall(function() handoffTrack:Stop(0.12) end)
        ghostHandoffTracks[handoffTrack] = nil
    end
    for _, conn in ipairs(animConns) do conn:Disconnect() end
    animConns = {}
    for _, track in pairs(trk) do pcall(function() track:Stop(0) end) end
    trk = {}
    CONFIG.REPLACE.reset()
    want, wantSpeed, lastTime, ours = {}, {}, {}, {}
    ov = nil
    if animateScript and animateScript.Parent then animateScript.Disabled = false end
    animateScript, animator = nil, nil
end

local function loadTrack(an, id, priority, looped)
    local animation = Instance.new("Animation")
    animation.AnimationId = id
    local track = an:LoadAnimation(animation)
    track.Priority = priority
    track.Looped = looped
    ours[track] = true
    local waited = 0
    while track.Length == 0 and waited < 3 do waited += task.wait() end
    return track
end

local function playTrack(track, fade, startTime, speed)
    want[track] = true
    wantSpeed[track] = speed
    track:Play(fade)
    if startTime then track.TimePosition = startTime end
    track:AdjustSpeed(speed)
    lastTime[track] = startTime or 0
end
local function stopTrack(track, fade)
    want[track] = false
    if track.IsPlaying then track:Stop(fade) end
end

local function setupAnimations(rig)
    clearAnimations()
    animToken += 1
    local my = animToken
    animHum, animHrp = rig.hum, rig.hrp
    local an = animHum:FindFirstChildOfClass("Animator") or animHum:WaitForChild("Animator", 3)
    if not an or not animHrp then warn("[PulseRevolver] no Animator / HumanoidRootPart found") return end
    animator = an
    animateScript = rig.char:FindFirstChild("Animate")
    if animateScript then animateScript.Disabled = true end
    for _, track in ipairs(an:GetPlayingAnimationTracks()) do track:Stop(0) end
    table.insert(animConns, an.AnimationPlayed:Connect(function(track)
        if not ours[track] and not isVoidAnimOurs(track) then
            track:Stop(0)
            CONFIG.REPLACE.handle(track) -- the current mode may play something else instead
        end
    end))
    local P = Enum.AnimationPriority
    local nt = {}
    nt.walk = loadTrack(an, ANIM.WALK, P.Action, true)
    local idleSpec, idle2Spec = CONFIG.IDLE.spec1, CONFIG.IDLE.spec2
    nt.idle = loadTrack(an, CONFIG.IDLE.normalize(idleSpec.id), idleSpec.priority or P.Action, idleSpec.kind == "loop")
    if idle2Spec then nt.idle2 = loadTrack(an, CONFIG.IDLE.normalize(idle2Spec.id), idle2Spec.priority or P.Action2, idle2Spec.kind == "loop") end
    local layerSpec = CONFIG.IDLE.layerSpec
    if layerSpec then nt.layer = loadTrack(an, CONFIG.IDLE.normalize(layerSpec.id), layerSpec.priority or P.Action3, false) end
    nt.taunt = loadTrack(an, ANIM.TAUNT, P.Action3, false)
    local shootId, flowingId = CONFIG.MOVEANIM.idsFor(CONFIG.MODES.list[CONFIG.MODES.index])
    nt.shoot1 = loadTrack(an, shootId, P.Action4, false)
    nt.flowing = loadTrack(an, flowingId, P.Action4, false)
    if CONFIG.FLING.isValidId(CONFIG.FLING.ANIMATION_ID) then
        nt.fling = loadTrack(an, CONFIG.FLING.normalizeId(CONFIG.FLING.ANIMATION_ID), P.Action4, false)
    end
    if my ~= animToken then return end
    trk = nt
    CONFIG.MOVEANIM.loadedShoot, CONFIG.MOVEANIM.loadedFlow, CONFIG.MOVEANIM.anim = shootId, flowingId, my
    stillTime, idle2ReadyAt, idleHeld, ov = 0, 0, false, nil
    animReady = true
    CONFIG.REPLACE.preload()
end

------------------------------------------------------------------
-- SOUND / AIM / HIT / BULLET
------------------------------------------------------------------
local function playSound(id, parent)
    if not parent then return end
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound.Volume = 1
    sound.RollOffMaxDistance = 150
    sound.Parent = parent
    sound.Ended:Connect(function() sound:Destroy() end)
    sound:Play()
    task.delay(20, function() if sound.Parent then sound:Destroy() end end)
end

------------------------------------------------------------------
-- LIGHTNING CANNON TRACER + SHOOT SOUND
-- Only used while the "Lightning Cannon" mode is selected. In that mode the E / R / C
-- moves make this squiggly neon lightning beam instead of the normal tracer, and play
-- lcshoot.mp3 (from your executor's workspace folder) instead of the normal fire sound.
------------------------------------------------------------------
CONFIG.LC = {
    MODE_NAME = "Lightning Cannon",
    SOUND_FILE = "lcshoot.mp3",    -- file in your executor's workspace folder
    SOUND_VOLUME = 1,
    BRICK_SIZE = Vector3.new(3, 3, 900),
    SEGMENTS = 14,                 -- segments per bolt (more = more squiggles)
    THICKNESS = 1.6,               -- how wide each bolt is
    MIN_OFFSET = 0.6,              -- min distance of a bolt from the brick's center (sideways and up/down)
    MAX_OFFSET = 1.8,              -- max distance of a bolt from the brick's center
    MAX_DRIFT = 1,                 -- slight diagonal: how far a bolt drifts over the full length
    SQUIGGLE = 1.0,                -- how far each joint zigs/zags off the line
    FADE_TIME = 0.9,               -- seconds for the beam to fade out
    MATCH_SHOT_LENGTH = false,     -- false: always BRICK_SIZE.Z long, starting at the muzzle. true: stretches to the full shot length like the normal tracer
    MAX_SEGMENTS = 150,            -- safety cap per bolt when MATCH_SHOT_LENGTH = true (long shots)
    FIRE_ANIM_ID = "111644455066361", -- when this replacement animation is playing, the gun fires after FIRE_DELAY
    FIRE_DELAY = 0.2,              -- seconds into that animation before the shot happens (shot also triggers the V move on the target it hits)
    -- hit effects (Lightning Cannon only)
    E_WHITE_HOLD = 0.6,            -- E move: seconds the target stays pure white before fading
    E_WHITE_FADE = 0.3,            -- E move: seconds the white takes to fade away
    FLASH_HOLD = 0.1,              -- replacement animation shot: white flash hold
    FLASH_FADE = 0.4,              -- replacement animation shot: white flash fade
    CUT_TIME = 0.6,                -- seconds the white copy takes to split apart and fade out
    CUT_DISTANCE_MIN = 3,          -- how far each limb flies sideways (studs, random between these)
    CUT_DISTANCE_MAX = 6,
    CUT_TILT_MIN = 20,             -- how far each limb tilts while flying off (degrees, random between these)
    CUT_TILT_MAX = 60,
    shotToken = 0,
    asset = nil,                   -- cached sound asset (false = could not load)
}

-- one bolt per corner: {sideways sign, up/down sign}
CONFIG.LC.corners = { {-1, 1}, {1, 1}, {-1, -1}, {1, -1} }
CONFIG.LC.rng = Random.new()

CONFIG.LC.isActive = function()
    local mode = CONFIG.MODES.list[CONFIG.MODES.index]
    return mode ~= nil and mode.text == CONFIG.LC.MODE_NAME
end

-- builds the lightning beam: brick + 4 squiggly bolts, all neon white, then fades it out
CONFIG.LC.beam = function(origin, endpoint)
    local L = CONFIG.LC
    local direction = endpoint - origin
    if direction.Magnitude < 0.5 then return end

    local length = L.BRICK_SIZE.Z
    local segments = L.SEGMENTS
    if L.MATCH_SHOT_LENGTH then
        length = math.min(direction.Magnitude, 2000) -- a Part cannot be longer than 2048 studs
        segments = math.clamp(math.ceil(length / (L.BRICK_SIZE.Z / L.SEGMENTS)), L.SEGMENTS, L.MAX_SEGMENTS)
    end
    local halfLength = length / 2

    -- the beam starts at the muzzle and points at the aim point
    local cf = CFrame.lookAt(origin, endpoint) * CFrame.new(0, 0, -halfLength)

    local beam = Instance.new("Model")
    beam.Name = "LightningCannonBeam"
    local parts = {}

    local function styleAndParent(part)
        part.Color = Color3.new(1, 1, 1)
        part.Material = Enum.Material.Neon
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Parent = beam
        table.insert(parts, part)
    end

    local brick = Instance.new("Part")
    brick.Name = "TracerBrick"
    brick.Size = Vector3.new(L.BRICK_SIZE.X, L.BRICK_SIZE.Y, length)
    brick.CFrame = cf
    styleAndParent(brick)

    local function makeSegment(a, b)
        local segLength = (b - a).Magnitude + L.THICKNESS * 0.6 -- small overlap so joints look solid
        local seg = Instance.new("Part")
        seg.Name = "BoltSegment"
        seg.Size = Vector3.new(L.THICKNESS, L.THICKNESS, segLength)
        seg.CFrame = CFrame.lookAt((a + b) / 2, b)
        styleAndParent(seg)
    end

    local rng = L.rng
    for _, c in ipairs(L.corners) do
        local signX, signY = c[1], c[2]

        -- slightly random start spot inside this corner
        local startX = signX * rng:NextNumber(L.MIN_OFFSET, L.MAX_OFFSET)
        local startY = signY * rng:NextNumber(L.MIN_OFFSET, L.MAX_OFFSET)

        -- slight diagonal: end spot drifts a little, but stays inside the same corner
        local endX = signX * math.clamp(math.abs(startX) + rng:NextNumber(-L.MAX_DRIFT, L.MAX_DRIFT), L.MIN_OFFSET, L.MAX_OFFSET)
        local endY = signY * math.clamp(math.abs(startY) + rng:NextNumber(-L.MAX_DRIFT, L.MAX_DRIFT), L.MIN_OFFSET, L.MAX_OFFSET)

        local points = {}
        for s = 0, segments do
            local t = s / segments
            local z = halfLength - t * length
            local x = startX + (endX - startX) * t
            local y = startY + (endY - startY) * t
            -- squiggle the middle joints, keep the two ends on the line
            if s > 0 and s < segments then
                x += rng:NextNumber(-L.SQUIGGLE, L.SQUIGGLE)
                y += rng:NextNumber(-L.SQUIGGLE, L.SQUIGGLE)
            end
            table.insert(points, cf:PointToWorldSpace(Vector3.new(x, y, z)))
        end
        for s = 1, #points - 1 do
            makeSegment(points[s], points[s + 1])
        end
    end

    beam.Parent = workspace

    -- fade everything out together, then remove the beam
    local info = TweenInfo.new(L.FADE_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local TweenService = game:GetService("TweenService")
    for _, part in ipairs(parts) do
        TweenService:Create(part, info, { Transparency = 1 }):Play()
    end
    task.delay(L.FADE_TIME + 0.1, function()
        if beam then beam:Destroy() end
    end)
end

-- loads lcshoot.mp3 from the workspace folder (same method the theme music uses)
CONFIG.LC.loadSound = function()
    local L = CONFIG.LC
    if L.asset ~= nil then return L.asset or nil end
    local assetFn = (type(getcustomasset) == "function" and getcustomasset) or (type(getsynasset) == "function" and getsynasset) or nil
    if not (type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function" and assetFn) then
        warn("[PulseRevolver][lightning cannon] your executor does not support isfile/readfile/writefile/getcustomasset - using the normal fire sound")
        L.asset = false
        return nil
    end
    if not isfile(L.SOUND_FILE) then
        warn("[PulseRevolver][lightning cannon] " .. L.SOUND_FILE .. " was not found in your workspace folder - using the normal fire sound")
        L.asset = false
        return nil
    end
    local okRead, data = pcall(readfile, L.SOUND_FILE)
    if not okRead or type(data) ~= "string" or #data == 0 then
        warn("[PulseRevolver][lightning cannon] " .. L.SOUND_FILE .. " could not be read or is empty - using the normal fire sound")
        L.asset = false
        return nil
    end
    -- cache copy named after the file's size + a checksum, so a changed file always gets a fresh name
    local sum = 0
    for i = 1, #data, 4099 do
        sum = (sum + string.byte(data, i) * (i % 251 + 1)) % 1000003
    end
    local cacheName = "LCShoot_cache_" .. #data .. "_" .. sum .. ".mp3"
    local okAsset, asset = pcall(function()
        if not isfile(cacheName) then writefile(cacheName, data) end
        return assetFn(cacheName)
    end)
    if not okAsset or not asset or asset == "" then
        warn("[PulseRevolver][lightning cannon] getcustomasset failed for " .. L.SOUND_FILE .. ": " .. tostring(asset) .. " - using the normal fire sound")
        L.asset = false
        return nil
    end
    L.asset = asset
    return asset
end
task.spawn(CONFIG.LC.loadSound) -- load it ahead of time so the first shot is not delayed

-- the fire sound for every move: lcshoot.mp3 in Lightning Cannon mode, otherwise the normal sound id
CONFIG.LC.playFire = function(normalId, parent)
    local L = CONFIG.LC
    if not parent then return end
    if CONFIG.IL.isActive() then
        CONFIG.IL.playFireSound(parent) -- Immortality Lord: its own sound instead of the bullet sound
        return
    end
    if L.isActive() then
        local asset = L.loadSound()
        if asset then
            local sound = Instance.new("Sound")
            sound.SoundId = asset
            sound.Volume = L.SOUND_VOLUME
            sound.RollOffMaxDistance = 150
            sound.Parent = parent
            sound.Ended:Connect(function() sound:Destroy() end)
            sound:Play()
            task.delay(20, function() if sound.Parent then sound:Destroy() end end)
            return
        end
    end
    playSound(normalId, parent)
end


local function getAimPoint()
    local cam = workspace.CurrentCamera
    if not cam then return nil, nil end
    local mouse = UserInputService:GetMouseLocation()
    local candidates, seen = {}, {}
    local function add(mdl)
        if mdl and mdl:IsA("Model") and not seen[mdl] then seen[mdl] = true table.insert(candidates, mdl) end
    end
    local liveFolder = workspace:FindFirstChild("Live")
    if liveFolder then for _, mdl in ipairs(liveFolder:GetChildren()) do add(mdl) end end
    for _, plr in ipairs(Players:GetPlayers()) do if plr ~= player then add(plr.Character) end end
    local myChar = player.Character
    local best, bestD, bestModel = nil, CONFIG.AIM_FOV, nil
    for _, mdl in ipairs(candidates) do
        local isMe = mdl == myChar or mdl.Name == player.Name or (myChar and mdl:IsDescendantOf(myChar))
        if not isMe then
            local hrp = mdl:FindFirstChild("HumanoidRootPart")
            local hum = mdl:FindFirstChildOfClass("Humanoid")
            if hrp and hrp:IsA("BasePart") and (not hum or hum.Health > 0) then
                local screenPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local distance = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
                    if distance <= bestD then best, bestD, bestModel = hrp.Position, distance, mdl end
                end
            end
        end
    end
    if best then return best, bestModel end
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { player.Character }
    if model then table.insert(ignore, model) end
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    if hit then
        local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
        if mdl and mdl:FindFirstChildOfClass("Humanoid") and mdl ~= myChar and mdl.Name ~= player.Name then
            return hit.Position, mdl
        end
        return hit.Position, nil
    end
    return ray.Origin + ray.Direction * 1000, nil
end

-- Picks the living character whose projected root is closest to the cursor.
-- This selection is separate from the barrel-forward projectile ray.
CONFIG.FLOW.getClosestTargetToCursor = function(fov)
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local candidates, seen = {}, {}
    local function add(mdl)
        if mdl and mdl:IsA("Model") and not seen[mdl] then
            seen[mdl] = true
            table.insert(candidates, mdl)
        end
    end
    local liveFolder = workspace:FindFirstChild("Live")
    if liveFolder then
        for _, mdl in ipairs(liveFolder:GetChildren()) do add(mdl) end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then add(plr.Character) end
    end
    local myChar = player.Character
    local bestModel, bestDistance = nil, fov or CONFIG.AIM_FOV_FLOWING
    for _, mdl in ipairs(candidates) do
        local isMe = mdl == myChar or mdl.Name == player.Name or (myChar and mdl:IsDescendantOf(myChar))
        if not isMe then
            local hrp = mdl:FindFirstChild("HumanoidRootPart")
            local hum = mdl:FindFirstChildOfClass("Humanoid")
            if hrp and hrp:IsA("BasePart") and (not hum or hum.Health > 0) then
                local screenPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local distance = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
                    if distance <= bestDistance then bestModel, bestDistance = mdl, distance end
                end
            end
        end
    end
    return bestModel
end

local function hitEffect(target)
    if not target or not target.Parent then return end
    local old = target:FindFirstChild("PulseHit")
    if old then old:Destroy() end
    local highlight = Instance.new("Highlight")
    highlight.Name = "PulseHit"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.15
    highlight.OutlineTransparency = 0
    highlight.FillColor = Color3.fromHSV(math.random(), 1, 1)
    highlight.OutlineColor = Color3.fromHSV(math.random(), 1, 1)
    highlight.Adornee = target
    highlight.Parent = target
    task.spawn(function()
        local start, nextSwap = os.clock(), 0
        local total = CONFIG.HIT_FLASH_TIME + CONFIG.HIT_FADE_TIME
        while highlight.Parent do
            local t = os.clock() - start
            if t >= total then break end
            if t < CONFIG.HIT_FLASH_TIME then
                if t >= nextSwap then
                    nextSwap = t + CONFIG.HIT_FLASH_RATE
                    highlight.FillColor = Color3.fromHSV(math.random(), 1, 1)
                    highlight.OutlineColor = Color3.fromHSV(math.random(), 1, 1)
                end
            else
                local alpha = (t - CONFIG.HIT_FLASH_TIME) / CONFIG.HIT_FADE_TIME
                highlight.FillTransparency = 0.15 + 0.85 * alpha
                highlight.OutlineTransparency = alpha
            end
            RunService.Heartbeat:Wait()
        end
        if highlight.Parent then highlight:Destroy() end
    end)
end

local function fireBullet()
    local firingRoot = getRoot()
    local firingCFrame = firingRoot and firingRoot.CFrame or nil
    local zone = muzzleZone
    local origin = zone and zone.Position or (animHrp and animHrp.Position)
    if not origin then return end
    CONFIG.LC.playFire(CONFIG.SOUND_FIRE, zone or animHrp)
    local target, targetModel = getAimPoint()
    if not target then return end
    local length = (target - origin).Magnitude
    if length < 0.5 then return end
    if CONFIG.LC.isActive() then
        -- Lightning Cannon: lightning beam instead of the normal tracer (hit effect + orbit still happen)
        CONFIG.LC.beam(origin, target)
        if targetModel then
            CONFIG.LC.hitCut(targetModel, origin, target) -- white target + white copy that splits apart
            triggerOrbitSequence(targetModel, firingCFrame)
            if not orbitEnabled then CONFIG.HIDE.restoreAfter(targetModel, CONFIG.LC.CUT_TIME) end
        end
        return
    end
    local beam = Instance.new("Part")
    beam.Name = "PulseBeam"
    beam.Shape = Enum.PartType.Cylinder
    beam.Material = M.Neon
    beam.Color = live.muzzle
    beam.Transparency = 1
    beam.Anchored = true
    beam.CanCollide = false
    beam.CanTouch = false
    beam.CanQuery = false
    beam.CastShadow = false
    beam.Size = Vector3.new(length, CONFIG.BULLET_THICKNESS, CONFIG.BULLET_THICKNESS)
    beam.CFrame = CFrame.lookAt((origin + target) / 2, target) * CFrame.Angles(0, math.pi / 2, 0)
    beam.Parent = workspace
    if targetModel then
        hitEffect(targetModel)
        triggerOrbitSequence(targetModel, firingCFrame)
    end
    local fadeIn, hold, fadeOut = CONFIG.BULLET_FADE_IN, CONFIG.BULLET_HOLD, CONFIG.BULLET_FADE_OUT
    local start = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        local t = os.clock() - start
        if t >= fadeIn + hold + fadeOut then conn:Disconnect() beam:Destroy() return end
        if t < fadeIn then beam.Transparency = 1 - t / fadeIn
        elseif t < fadeIn + hold then beam.Transparency = 0
        else beam.Transparency = (t - fadeIn - hold) / fadeOut end
        beam.Color = live.muzzle
    end)
end

-- Lightning Cannon hit effects ------------------------------------------------
-- pure white highlight on the target (replaces the random-colour flashing)
CONFIG.LC.whiteHit = function(target, hold, fade, color, fadeIn)
    if not target or not target.Parent then return end
    color = color or Color3.new(1, 1, 1)
    fadeIn = fadeIn or 0
    local old = target:FindFirstChild("PulseHit")
    if old then old:Destroy() end
    local highlight = Instance.new("Highlight")
    highlight.Name = "PulseHit"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = fadeIn > 0 and 1 or 0
    highlight.OutlineTransparency = fadeIn > 0 and 1 or 0
    highlight.Adornee = target
    highlight.Parent = target
    task.spawn(function()
        local start = os.clock()
        while highlight.Parent do
            local t = os.clock() - start
            if t >= fadeIn + hold + fade then break end
            local alpha = 0
            if t < fadeIn then
                alpha = 1 - t / math.max(fadeIn, 0.01)          -- fading in to the colour
            elseif t >= fadeIn + hold then
                alpha = (t - fadeIn - hold) / math.max(fade, 0.01) -- fading back out
            end
            highlight.FillTransparency = alpha
            highlight.OutlineTransparency = alpha
            RunService.Heartbeat:Wait()
        end
        if highlight.Parent then highlight:Destroy() end
    end)
end

-- a pure white copy of the target, made in the exact same spot, whose limbs split off to the
-- left / right (relative to the shot) while it fades out
CONFIG.LC.cutClone = function(target, shotDir, opts)
    local L = CONFIG.LC
    local rng = L.rng
    opts = opts or {}
    local cloneColor = opts.color or Color3.new(1, 1, 1)
    local cloneMaterial = opts.material or Enum.Material.Neon
    local shrink = opts.shrink == true -- true: limbs shrink to nothing instead of fading out
    local cutTime = opts.time or L.CUT_TIME
    if not target or not target.Parent then return end

    -- characters are sometimes not Archivable, so allow it just for the copy
    local changed = {}
    for _, d in ipairs(target:GetDescendants()) do
        if not d.Archivable then
            d.Archivable = true
            table.insert(changed, d)
        end
    end
    if not target.Archivable then
        target.Archivable = true
        table.insert(changed, target)
    end
    local okClone, clone = pcall(function() return target:Clone() end)
    for _, d in ipairs(changed) do pcall(function() d.Archivable = false end) end
    if not okClone or not clone then return end

    -- strip everything that is not a plain visible part (scripts, humanoid, sounds, clothes, joints ...)
    local junk = { "Humanoid", "LuaSourceContainer", "Sound", "ParticleEmitter", "Beam", "Trail", "Light",
        "Highlight", "LayerCollector", "Decal", "SurfaceAppearance", "Clothing", "ShirtGraphic",
        "CharacterMesh", "BodyColors", "JointInstance", "WeldConstraint", "Constraint", "ForceField",
        "Fire", "Smoke", "Sparkles", "Explosion" }
    for _, d in ipairs(clone:GetDescendants()) do
        for _, className in ipairs(junk) do
            if d:IsA(className) then
                d:Destroy()
                break
            end
        end
    end

    -- every remaining part: pure white neon, anchored, no collision
    local bodyParts, otherParts = {}, {}
    local meshScales = {}
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            if d.Transparency >= 0.95 or d.Name == "HumanoidRootPart" then
                d:Destroy()
            else
                d.Anchored = true
                d.CanCollide = false
                d.CanTouch = false
                d.CanQuery = false
                d.CastShadow = false
                d.Color = cloneColor
                d.Material = cloneMaterial
                d.Transparency = 0
                if d:IsA("MeshPart") then d.TextureID = "" end
                if d.Parent == clone then table.insert(bodyParts, d) else table.insert(otherParts, d) end
            end
        elseif d:IsA("SpecialMesh") then
            d.TextureId = ""
            if d.MeshType == Enum.MeshType.FileMesh then meshScales[d] = d.Scale end
        end
    end
    if #bodyParts == 0 then bodyParts, otherParts = otherParts, {} end
    if #bodyParts == 0 then clone:Destroy() return end

    -- "left" / "right" are relative to the shot direction
    local dir = (shotDir and shotDir.Magnitude > 0.001) and shotDir.Unit or Vector3.zAxis
    local right = dir:Cross(Vector3.yAxis)
    if right.Magnitude < 0.05 then right = Vector3.xAxis else right = right.Unit end

    local center = Vector3.zero
    for _, p in ipairs(bodyParts) do center += p.Position end
    center /= #bodyParts

    -- each body part is a "limb"; accessories / extra parts follow the closest limb
    local groups = {}
    for _, p in ipairs(bodyParts) do
        local side = (p.Position - center):Dot(right)
        local sign = side > 0.3 and 1 or (side < -0.3 and -1 or (rng:NextInteger(0, 1) == 0 and -1 or 1))
        table.insert(groups, {
            pivot = p.Position,
            sign = sign,
            dist = rng:NextNumber(L.CUT_DISTANCE_MIN, L.CUT_DISTANCE_MAX),
            lift = rng:NextNumber(-0.8, 0.8),
            tilt = math.rad(rng:NextNumber(L.CUT_TILT_MIN, L.CUT_TILT_MAX)) * sign,
            parts = { p },
            origCF = { p.CFrame },
            origSize = { p.Size },
        })
    end
    for _, p in ipairs(otherParts) do
        local best, bestDistance = nil, math.huge
        for _, g in ipairs(groups) do
            local distance = (g.pivot - p.Position).Magnitude
            if distance < bestDistance then best, bestDistance = g, distance end
        end
        if best then
            table.insert(best.parts, p)
            table.insert(best.origCF, p.CFrame)
            table.insert(best.origSize, p.Size)
        end
    end

    clone.Name = "LightningCannonCut"
    clone.Parent = workspace

    local start = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        local a = (os.clock() - start) / math.max(cutTime, 0.01)
        if a >= 1 or not clone.Parent then
            conn:Disconnect()
            clone:Destroy()
            return
        end
        local e = 1 - (1 - a) * (1 - a) -- eases out: fast split, slows down while fading
        local k = math.max(1 - a, 0.02)  -- shrink factor (1 -> 0)
        if shrink then
            for mesh, originalScale in pairs(meshScales) do mesh.Scale = originalScale * k end
        end
        for _, g in ipairs(groups) do
            local offset = right * (g.sign * g.dist * e) + Vector3.new(0, g.lift * e, 0)
            local delta = CFrame.new(offset) * CFrame.new(g.pivot) * CFrame.fromAxisAngle(dir, g.tilt * e) * CFrame.new(-g.pivot)
            for i, p in ipairs(g.parts) do
                p.CFrame = delta * g.origCF[i]
                if shrink then p.Size = g.origSize[i] * k else p.Transparency = a end
            end
        end
    end)
    return true
end

-- E move hit: white target + the white copy that splits apart
CONFIG.LC.hitCut = function(target, origin, aimPoint)
    local L = CONFIG.LC
    local ok, made = pcall(L.cutClone, target, aimPoint - origin) -- copy first, so the highlight is not copied
    if not ok then warn("[PulseRevolver][lightning cannon] clone effect failed: " .. tostring(made)) end
    if ok and made then
        CONFIG.HIDE.hide(target) -- the original vanishes instantly, only the copy splits apart
    else
        L.whiteHit(target, L.E_WHITE_HOLD, L.E_WHITE_FADE)
    end
end

-- replacement animation shot hit: just a white flash, no copy
CONFIG.LC.hitFlash = function(target)
    local L = CONFIG.LC
    L.whiteHit(target, L.FLASH_HOLD, L.FLASH_FADE)
end

-- Per-mode move animations (CONFIG.MODES.list[...].moves) -------------------------
CONFIG.MOVEANIM = {}
CONFIG.MOVEANIM.idsFor = function(mode)
    local moves = mode and mode.moves
    local shootId = moves and moves.shoot and moves.shoot.id
    local flowId = moves and moves.flowing and moves.flowing.id
    return shootId and ("rbxassetid://" .. shootId) or ANIM.SHOOT1, flowId and ("rbxassetid://" .. flowId) or ANIM.FLOWING
end
CONFIG.MOVEANIM.flowStart = function() -- where in the R animation the current mode starts playing it (seconds)
    local mode = CONFIG.MODES.list[CONFIG.MODES.index]
    local flowMove = mode and mode.moves and mode.moves.flowing
    return flowMove and flowMove.startTime or 0
end
-- called when the mode changes: loads the new mode's E/C and R animations and swaps them in
CONFIG.MOVEANIM.rebuild = function()
    local M = CONFIG.MOVEANIM
    if not animReady or not animator then return end
    local shootId, flowId = M.idsFor(CONFIG.MODES.list[CONFIG.MODES.index])
    if M.anim == animToken and M.loadedShoot == shootId and M.loadedFlow == flowId then return end
    M.token = (M.token or 0) + 1
    local token, myAnim, an = M.token, animToken, animator
    task.spawn(function()
        local P = Enum.AnimationPriority
        local newShoot = loadTrack(an, shootId, P.Action4, false)
        local newFlow = loadTrack(an, flowId, P.Action4, false)
        if deleted or token ~= M.token or myAnim ~= animToken then return end
        for _, old in ipairs({ trk.shoot1, trk.flowing }) do
            want[old] = nil
            pcall(function() old:Stop(0.1) end)
        end
        if ov == "shoot1" or ov == "flowing" then ov = nil end
        CONFIG.DELETE.pending, CONFIG.FLOW.fired = false, false
        trk.shoot1, trk.flowing = newShoot, newFlow
        M.loadedShoot, M.loadedFlow, M.anim = shootId, flowId, myAnim
    end)
end

-- Immortality Lord: sword moves ------------------------------------------------
-- E / C animation = moves.shoot, R animation = moves.flowing (see the mode entry)
-- E: no bullet. fireTime seconds into the animation the closest target within E_RADIUS studs gets hit.
-- R: no bullet. fireDelay seconds after it starts, the target closest to the cursor within R_RADIUS studs is picked.
CONFIG.IL = {
    MODE_NAME = "Immortality Lord",
    E_RADIUS = 50,                 -- studs: how close a target must be for E to hit (closest one only)
    R_RADIUS = 150,                 -- studs: how close a target must be for R to pick it (closest to the cursor)
    HIT_COLOR = Color3.new(0, 0, 0),         -- the target goes black...
    HIT_FADE_IN = 0.15,            -- ...fading into black over this many seconds
    HIT_HOLD = 0.6,                -- stays black this long
    HIT_FADE = 0.3,                -- then fades back
    CLONE_COLOR = Color3.new(0, 0, 0),       -- the black copy that splits apart
    CLONE_MATERIAL = Enum.Material.SmoothPlastic,
    CLONE_TIME = 1.6,              -- seconds for the copy to split and shrink to nothing
    SOUND_HIT = 17871250897,       -- plays when an E move hits a target (global: you hear it from anywhere)
    SOUND_HIT_VOLUME = 1,
    SOUND_FIRE = 137628815514180,  -- plays instead of the bullet sound for E / C / R
    SOUND_FIRE_START = 0.1,        -- seconds into the fire sound where it starts playing (skips a delay at the start of the file)
}

CONFIG.IL.isActive = function()
    local mode = CONFIG.MODES.list[CONFIG.MODES.index]
    return mode ~= nil and mode.text == CONFIG.IL.MODE_NAME
end

-- the Immortality Lord fire sound, starting SOUND_FIRE_START seconds into the file
CONFIG.IL.playFireSound = function(parent)
    local I = CONFIG.IL
    if not parent then return end
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(I.SOUND_FIRE)
    sound.Volume = 1
    sound.RollOffMaxDistance = 150
    sound.TimePosition = I.SOUND_FIRE_START
    sound.Parent = parent
    sound.Ended:Connect(function() sound:Destroy() end)
    sound:Play()
    -- if the file was not loaded yet the start position can be ignored, so set it again once it is loaded
    if not sound.IsLoaded then
        task.spawn(function()
            sound.Loaded:Wait()
            if sound.Parent and sound.TimePosition < I.SOUND_FIRE_START then sound.TimePosition = I.SOUND_FIRE_START end
        end)
    end
    task.delay(20, function() if sound.Parent then sound:Destroy() end end)
end
-- plays a sound globally (not tied to a position), so it is heard at the same volume from anywhere
CONFIG.IL.playGlobalSound = function(id, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(id)
    sound.Volume = volume or 1
    sound.Parent = game:GetService("SoundService")
    sound.Ended:Connect(function() sound:Destroy() end)
    sound:Play()
    task.delay(20, function() if sound.Parent then sound:Destroy() end end)
end
-- load the file ahead of time so the start position works on the very first shot
task.spawn(function()
    local preload = Instance.new("Sound")
    preload.SoundId = "rbxassetid://" .. tostring(CONFIG.IL.SOUND_FIRE)
    pcall(function() game:GetService("ContentProvider"):PreloadAsync({ preload }) end)
    preload:Destroy()
end)

-- living characters other than us: { model, hrp }
CONFIG.IL.candidates = function()
    local list, seen = {}, {}
    local myChar = player.Character
    local function add(mdl)
        if mdl and mdl:IsA("Model") and not seen[mdl] then
            seen[mdl] = true
            local isMe = mdl == myChar or mdl.Name == player.Name or (myChar and mdl:IsDescendantOf(myChar))
            if not isMe then
                local hrp = mdl:FindFirstChild("HumanoidRootPart")
                local hum = mdl:FindFirstChildOfClass("Humanoid")
                if hrp and hrp:IsA("BasePart") and (not hum or hum.Health > 0) then
                    table.insert(list, { model = mdl, hrp = hrp })
                end
            end
        end
    end
    local liveFolder = workspace:FindFirstChild("Live")
    if liveFolder then for _, mdl in ipairs(liveFolder:GetChildren()) do add(mdl) end end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then add(plr.Character) end
    end
    return list
end

-- the single closest target within radius studs of us
CONFIG.IL.closest = function(radius)
    local root = getRoot()
    if not root then return nil end
    local best, bestDistance = nil, radius
    for _, c in ipairs(CONFIG.IL.candidates()) do
        local distance = (c.hrp.Position - root.Position).Magnitude
        if distance <= bestDistance then best, bestDistance = c, distance end
    end
    return best and best.model, best and best.hrp
end

-- the target closest to the cursor (on screen) among those within radius studs of us
CONFIG.IL.closestToCursor = function(radius)
    local root, cam = getRoot(), workspace.CurrentCamera
    if not root or not cam then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local best, bestDistance = nil, math.huge
    for _, c in ipairs(CONFIG.IL.candidates()) do
        if (c.hrp.Position - root.Position).Magnitude <= radius then
            local screenPos, onScreen = cam:WorldToViewportPoint(c.hrp.Position)
            if onScreen then
                local distance = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
                if distance < bestDistance then best, bestDistance = c.model, distance end
            end
        end
    end
    return best
end

-- black hit: the target fades into black, and a black copy splits apart and shrinks to nothing
CONFIG.IL.hit = function(target, direction)
    local I, L = CONFIG.IL, CONFIG.LC
    local ok, made = pcall(L.cutClone, target, direction, {
        color = I.CLONE_COLOR, material = I.CLONE_MATERIAL, shrink = true, time = I.CLONE_TIME,
    })
    if not ok then warn("[PulseRevolver][immortality lord] clone effect failed: " .. tostring(made)) end
    if ok and made then
        CONFIG.HIDE.hide(target) -- the original vanishes instantly, only the copy splits apart
    else
        L.whiteHit(target, I.HIT_HOLD, I.HIT_FADE, I.HIT_COLOR, I.HIT_FADE_IN)
    end
end

-- E: runs fireTime seconds into the animation (instead of fireBullet)
CONFIG.IL.slash = function()
    local I = CONFIG.IL
    local root = getRoot()
    if not root then return end
    I.playFireSound(muzzleZone or animHrp)
    local targetModel, hrp = I.closest(I.E_RADIUS)
    if not targetModel then return end
    I.playGlobalSound(I.SOUND_HIT, I.SOUND_HIT_VOLUME) -- global: heard from anywhere, not just near the target
    I.hit(targetModel, hrp.Position - root.Position)
    triggerOrbitSequence(targetModel, root.CFrame) -- same follow-up a bullet hit has
    if not orbitEnabled then CONFIG.HIDE.restoreAfter(targetModel, I.CLONE_TIME) end
end

-- R: runs fireDelay seconds after the R animation starts (instead of the bullet code)
CONFIG.IL.flow = function()
    local I = CONFIG.IL
    local root = getRoot()
    I.playFireSound(muzzleZone or animHrp)
    local targetModel = I.closestToCursor(I.R_RADIUS)
    if targetModel then
        CONFIG.FLOW.triggerSequence(targetModel, root and root.CFrame or nil)
    end
end

-- Hide the original target while its split-apart copy plays -----------------------
-- The target is made invisible for us only (client side). It is made visible again as soon as we
-- teleport back to our real character (end of the E move), when the script is deleted, or after
-- SAFETY_TIME seconds, whichever comes first.
CONFIG.HIDE = { SAFETY_TIME = 15, hidden = {} }

CONFIG.HIDE.hide = function(target)
    local H = CONFIG.HIDE
    if not target or not target.Parent or H.hidden[target] then return end
    local entry = { parts = {}, faces = {} }
    for _, d in ipairs(target:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(entry.parts, { part = d, original = d.LocalTransparencyModifier })
            d.LocalTransparencyModifier = 1
        elseif d:IsA("FaceInstance") then -- decals / textures (the face) are not hidden by the part
            table.insert(entry.faces, { face = d, original = d.Transparency })
            d.Transparency = 1
        end
    end
    H.hidden[target] = entry
    task.delay(H.SAFETY_TIME, function()
        if H.hidden[target] == entry then H.restore(target) end
    end)
end

CONFIG.HIDE.restore = function(target)
    local H = CONFIG.HIDE
    local entry = H.hidden[target]
    if not entry then return end
    H.hidden[target] = nil
    for _, e in ipairs(entry.parts) do
        if e.part.Parent then e.part.LocalTransparencyModifier = e.original end
    end
    for _, e in ipairs(entry.faces) do
        if e.face.Parent then e.face.Transparency = e.original end
    end
end

CONFIG.HIDE.restoreAll = function()
    local H = CONFIG.HIDE
    local list = {}
    for target in pairs(H.hidden) do table.insert(list, target) end
    for _, target in ipairs(list) do H.restore(target) end
end

-- used when no orbit / teleport follows the hit: show the target again once the copy is done
CONFIG.HIDE.restoreAfter = function(target, seconds)
    task.delay(seconds, function() CONFIG.HIDE.restore(target) end)
end

-- Lightning Cannon animation shot: the gun fires (lightning tracer + sound, like E) and the V move
-- (Fling) is triggered on the target the shot hits
CONFIG.LC.fireShot = function()
    local L = CONFIG.LC
    local zone = muzzleZone
    local origin = zone and zone.Position or (animHrp and animHrp.Position)
    if not origin then return end
    L.playFire(CONFIG.SOUND_FIRE, zone or animHrp)
    local target, targetModel = getAimPoint()
    if not target then return end
    if (target - origin).Magnitude < 0.5 then return end
    L.beam(origin, target)
    if targetModel then
        L.hitFlash(targetModel) -- white flash, no copy
        local f = CONFIG.FLING
        -- same guards the V key uses: never start a second orbit while one is running
        if not (f.active or CONFIG.FLOW.active or orbitEnabled or animationVoidTrip) then
            f.trigger(targetModel)
        end
    end
end

-- called when a replacement animation starts playing (see CONFIG.REPLACE.handle)
CONFIG.LC.onReplacementPlayed = function(id, track)
    local L = CONFIG.LC
    if id ~= L.FIRE_ANIM_ID or not L.isActive() then return end
    L.shotToken += 1
    local my = L.shotToken
    task.spawn(function()
        -- wait until the animation has really played FIRE_DELAY seconds; if it gets cancelled first, no shot
        while not deleted and L.shotToken == my and track.IsPlaying and track.TimePosition < L.FIRE_DELAY do
            RunService.Heartbeat:Wait()
        end
        if deleted or L.shotToken ~= my or not track.IsPlaying or track.TimePosition < L.FIRE_DELAY then return end
        local ok, err = pcall(L.fireShot)
        if not ok then warn("[PulseRevolver][lightning cannon] shot failed: " .. tostring(err)) end
    end)
end

CONFIG.FLOW.triggerSequence = function(targetModel, firingCFrame)
    if not isValidShotTarget(targetModel) or animationVoidTrip then return end
    local shotCFrame = firingCFrame or (getRoot() and getRoot().CFrame)
    if not shotCFrame then return end

    disconnectDiagnosticConnections()
    diagnosticTrack, diagnosticTarget, diagnosticTargetHumanoid = nil, nil, nil
    shotReturnCFrame = shotCFrame
    ghostWorldCF = shotCFrame
    -- Fallback destination is the exact firing/clone spawn position.
    -- Never store the projectile ray endpoint here.
    CONFIG.FLOW.destination = shotCFrame
    CONFIG.FLOW.active = true
    CONFIG.FLOW.fired = true
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = CONFIG.FLOW.flowingToolName
    CONFIG.BRING.locked = CONFIG.BRING.modes[CONFIG.BRING.index]
    shotTargetModel = targetModel

    -- Ghost + camera first, THEN orbit: the real body must not move to the target
    -- until the camera is already following the clone.
    if not ghostModel then
        local char = getCharacter()
        if char and buildGhost(char, ghostWorldCF) then
            local cameraReady = saveAndSetGhostCamera()
            setRealBodyHidden(char, cameraReady)
        else
            ghostBuildRetryAt = os.clock() + 0.25
        end
    else
        pivotGhostRootTo(ghostWorldCF)
        saveAndSetGhostCamera()
    end
    orbitEnabled = true
    AV.setEnabled(true)
    diagnosticLastHandledTrack = nil
    diagnosticStatus = "Flowing Water armed; waiting for animation " .. CONFIG.FLOW.animationId
    diagnosticLastOutcome = "Flowing Water selected; Orbit enabled"
    CONFIG.FAILSAFE.deadline = os.clock() + CONFIG.FAILSAFE.TIMEOUT
end

CONFIG.FLOW.fireBullet = function()
    if CONFIG.IL.isActive() then CONFIG.IL.flow() return end -- Immortality Lord: no bullet, picks the target closest to the cursor
    local firingRoot = getRoot()
    local firingCFrame = firingRoot and firingRoot.CFrame or nil
    local zone = muzzleZone
    local origin = zone and zone.Position or (animHrp and animHrp.Position)
    if not origin then return end

    -- The weapon is built along local -Z, which is the barrel's LookVector.
    local direction = zone and zone.CFrame.LookVector or (firingRoot and firingRoot.CFrame.LookVector)
    if not direction or direction.Magnitude < 0.001 then return end
    direction = direction.Unit

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { player.Character }
    if model then table.insert(ignore, model) end
    if ghostModel then table.insert(ignore, ghostModel) end
    params.FilterDescendantsInstances = ignore
    local rayResult = workspace:Raycast(origin, direction * 1000, params)
    local endpoint = rayResult and rayResult.Position or (origin + direction * 1000)

    CONFIG.LC.playFire(CONFIG.SOUND_FLOWING_FIRE, zone or animHrp)

    local beamLength = (endpoint - origin).Magnitude
    if beamLength > 0.5 and CONFIG.LC.isActive() then
        CONFIG.LC.beam(origin, endpoint) -- Lightning Cannon: lightning beam instead of the normal tracer
    elseif beamLength > 0.5 then
        local thickness = CONFIG.BULLET_THICKNESS * CONFIG.FLOWING_BULLET_SIZE_MULTIPLIER
        local beam = Instance.new("Part")
        beam.Name = "FlowingWaterBeam"
        beam.Shape = Enum.PartType.Cylinder
        beam.Material = M.Neon
        beam.Color = live.muzzle
        beam.Transparency = 1
        beam.Anchored = true
        beam.CanCollide = false
        beam.CanTouch = false
        beam.CanQuery = false
        beam.CastShadow = false
        beam.Size = Vector3.new(beamLength, thickness, thickness)
        beam.CFrame = CFrame.lookAt((origin + endpoint) / 2, endpoint) * CFrame.Angles(0, math.pi / 2, 0)
        beam.Parent = workspace

        local multiplier = CONFIG.FLOWING_BULLET_TIME_MULTIPLIER
        local fadeIn = CONFIG.BULLET_FADE_IN * multiplier
        local hold = CONFIG.BULLET_HOLD * multiplier
        local fadeOut = CONFIG.BULLET_FADE_OUT * multiplier
        local start = os.clock()
        local conn
        conn = RunService.Heartbeat:Connect(function()
            local t = os.clock() - start
            if t >= fadeIn + hold + fadeOut then
                conn:Disconnect()
                beam:Destroy()
                return
            end
            if t < fadeIn then beam.Transparency = 1 - t / fadeIn
            elseif t < fadeIn + hold then beam.Transparency = 0
            else beam.Transparency = (t - fadeIn - hold) / fadeOut end
            beam.Color = live.muzzle
        end)
    end

    local targetModel = CONFIG.FLOW.getClosestTargetToCursor()
    if targetModel then
        CONFIG.FLOW.triggerSequence(targetModel, firingCFrame)
    end
end

-- reused list (no per-frame allocation): { idle, idle2 }
Perf.idleList = {}
function Perf.idleTracks(t)
    local list = Perf.idleList
    list[1], list[2] = t.idle, t.idle2
    return list
end

local function animStep(dt)
    if not animReady or not animator or not animator.Parent or not animHrp or not animHrp.Parent then return end
    for handoffTrack, stopAt in pairs(ghostHandoffTracks) do
        if not handoffTrack.IsPlaying then ghostHandoffTracks[handoffTrack] = nil
        elseif os.clock() >= stopAt then ghostHandoffTracks[handoffTrack] = nil handoffTrack:Stop(0.18) end
    end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if not ours[track] and not isVoidAnimOurs(track) then
            track:Stop(0)
            CONFIG.REPLACE.handle(track)
        end
    end
    for track, shouldPlay in pairs(want) do
        if shouldPlay then
            if track.IsPlaying then lastTime[track] = track.TimePosition
            else
                track:Play(0)
                track.TimePosition = lastTime[track] or 0
                track:AdjustSpeed(wantSpeed[track] or 1)
            end
        end
    end
    local velocity = animHrp.AssemblyLinearVelocity
    local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local grace = Perf.handoffMove
    if grace and (speed > 0.6 or os.clock() >= grace.untilT) then Perf.handoffMove, grace = nil, nil end
    local moving = speed > 0.6 or grace ~= nil
    if ghostModel then
        -- While the clone is shown the real body is parked / orbiting / in the void: its velocity is noise and
        -- flipped "moving" on and off many times a second. Every flip stopped and restarted the real idle, and the clone
        -- mirrors that idle, so it flickered between idle and no idle. The clone's own movement decides instead.
        moving = Perf.ghostMoving == true
    end
    if moving then stillTime = 0 else stillTime += dt end
    local currentMode = CONFIG.MODES.list[CONFIG.MODES.index]
    local noWalkAnim = currentMode ~= nil and currentMode.noWalkAnim == true -- this mode keeps its idle animation while walking
    if moving and not noWalkAnim then
        if not want[trk.walk] then stopTrack(trk.idle, 0.2) playTrack(trk.walk, 0.2, nil, 1) end
        for _, idleTrack in ipairs(Perf.idleTracks(trk)) do
            if want[idleTrack] then
                Perf.idleStopAt[idleTrack] = os.clock()
                stopTrack(idleTrack, 0.15)
            elseif idleTrack.IsPlaying and os.clock() - (Perf.idleStopAt[idleTrack] or 0) > 0.4 then
                -- an idle that is still playing although it is not wanted while we walk: kill it
                Perf.idleStopAt[idleTrack] = os.clock()
                idleTrack:Stop(0.1)
            end
        end
        local walkSpeed = grace and grace.speed or math.clamp(speed / CONFIG.WALK_REF_SPEED, 0.2, 3)
        wantSpeed[trk.walk] = walkSpeed
        trk.walk:AdjustSpeed(walkSpeed)
    else
        if want[trk.walk] then stopTrack(trk.walk, 0.2) end
        if not want[trk.idle] then CONFIG.IDLE.begin(1) end
    end
    CONFIG.IDLE.step(dt, moving)
    CONFIG.IDLE.layerStep(dt)
    if ov == "taunt" then
        local track = trk.taunt
        if track.TimePosition >= math.min(CONFIG.TAUNT_TIME, track.Length - 0.03) then stopTrack(track, 0.2) ov = nil end
    elseif ov == "shoot1" then
        local track = trk.shoot1
        local shootMove = currentMode and currentMode.moves and currentMode.moves.shoot
        local shootFireTime = shootMove and shootMove.fireTime or CONFIG.SHOOT1_TIME
        if track.TimePosition >= math.min(shootFireTime, track.Length - 0.03) then
            stopTrack(track, 0.1)
            ov = nil
            if CONFIG.DELETE.pending then
                CONFIG.DELETE.pending = false
                CONFIG.DELETE.fire()
            elseif CONFIG.IL.isActive() then
                CONFIG.IL.slash() -- Immortality Lord: sword check instead of a bullet
            else
                fireBullet()
            end
        end
    elseif ov == "fling" then
        local track = trk.fling
        if track and track.IsPlaying then
            if track.Length > 0 and track.TimePosition >= track.Length - 0.03 then
                stopTrack(track, 0.12)
                ov = nil
            end
        else
            ov = nil
        end
    elseif ov == "flowing" then
        local track = trk.flowing
        if track and track.IsPlaying then
            local flowMove = currentMode and currentMode.moves and currentMode.moves.flowing
            local flowFireTime = flowMove and ((flowMove.startTime or 0) + (flowMove.fireDelay or 0)) or CONFIG.FLOWING_FIRE_TIME
            if not CONFIG.FLOW.fired and track.TimePosition >= flowFireTime then
                CONFIG.FLOW.fired = true
                CONFIG.FLOW.fireBullet()
            end
            if track.Length > 0 and track.TimePosition >= track.Length - 0.03 then
                stopTrack(track, 0.12)
                ov = nil
                CONFIG.FLOW.fired = false
            end
        else
            ov = nil
            CONFIG.FLOW.fired = false
        end
    end
end

local function startTaunt()
    if not animReady or ov or CONFIG.FLOW.active then return end
    ov = "taunt"
    playTrack(trk.taunt, 0.1, 0, 1)
    playSound(CONFIG.SOUND_TAUNT, animHrp)
end
local function startShoot()
    if not animReady or isToolOnCooldown("primary") or CONFIG.FLOW.active then return end
    if ov == "shoot1" or ov == "flowing" then return end
    if ov == "taunt" then stopTrack(trk.taunt, 0.1) end
    CONFIG.DELETE.pending = false
    ov = "shoot1"
    playTrack(trk.shoot1, 0.05, 0, 1)
end
CONFIG.FLOW.start = function()
    if not animReady or isToolOnCooldown("flowing") or CONFIG.FLOW.active or orbitEnabled then return end
    if ov == "shoot1" or ov == "flowing" then return end
    if ov == "taunt" then stopTrack(trk.taunt, 0.1) end
    CONFIG.FLOW.fired = false
    ov = "flowing"
    playTrack(trk.flowing, 0.05, CONFIG.MOVEANIM.flowStart(), 1)
end

------------------------------------------------------------------
-- FLING (V): animation + sound, orbit the target while sweeping the orbit distance
------------------------------------------------------------------
function CONFIG.FLING.isValidId(id)
    local digits = tostring(id or ""):match("%d+")
    return digits ~= nil and tonumber(digits) ~= 0
end
function CONFIG.FLING.normalizeId(id)
    return "rbxassetid://" .. tostring(id):match("%d+")
end
function CONFIG.FLING.reset()
    CONFIG.FLING.active, CONFIG.FLING.startedAt, CONFIG.FLING.sweepStart = false, nil, nil
    CONFIG.FLING.rotation, CONFIG.FLING.axis, CONFIG.FLING.axisAt = nil, nil, 0
end
-- distance for a given time into the sweep: FAR -> NEAR (-> FAR when ROUND_TRIP), repeated every LAP_TIME
function CONFIG.FLING.distanceAt(elapsed)
    local f = CONFIG.FLING
    local phase = (elapsed / f.LAP_TIME) % 1
    local alpha
    if f.ROUND_TRIP then alpha = phase < 0.5 and phase * 2 or (1 - phase) * 2
    else alpha = phase end
    return f.DISTANCE_FAR + (f.DISTANCE_NEAR - f.DISTANCE_FAR) * alpha
end
-- random spin axis over all directions (left/right, up/down, roll)
function CONFIG.FLING.randomAxis()
    local v = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
    if v.Magnitude < 0.05 then return Vector3.yAxis end
    return v.Unit
end
-- advance the random spin by dt; returns the current orientation (applied to our root while Fling runs)
function CONFIG.FLING.stepRotation(dt)
    local f = CONFIG.FLING
    local now = os.clock()
    if not f.rotation then
        -- completely random starting orientation
        f.rotation = CFrame.Angles(math.rad(math.random(0, 359)), math.rad(math.random(180, 180)), math.rad(math.random(0, 359)))
        f.axis, f.axisAt = f.randomAxis(), now
    elseif f.ROTATION_CHANGE_TIME > 0 and now - f.axisAt >= f.ROTATION_CHANGE_TIME then
        f.axis, f.axisAt = f.randomAxis(), now
    end
    f.rotation = f.rotation * CFrame.fromAxisAngle(f.axis, math.rad(f.ROTATION_SPEED) * dt)
    return f.rotation
end
-- Sweep done (or target gone): stop orbit + anti void and go back to the clone.
function CONFIG.FLING.finish(reason)
    if not CONFIG.FLING.active then return end
    CONFIG.FLING.reset()
    CONFIG.FAILSAFE.returnToClone(reason or "Fling finished")
end
CONFIG.FLING.trigger = function(targetModel)
    local f = CONFIG.FLING
    if not isValidShotTarget(targetModel) or animationVoidTrip or CONFIG.FLOW.active then return end
    local shotCFrame = getRoot() and getRoot().CFrame
    if not shotCFrame then return end
    disconnectDiagnosticConnections()
    diagnosticTrack, diagnosticTarget, diagnosticTargetHumanoid = nil, nil, nil
    shotReturnCFrame, ghostWorldCF = shotCFrame, shotCFrame
    CONFIG.FLOW.destination = nil
    CONFIG.FLOW.fired = false
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = f.TOOL_NAME
    shotTargetModel = targetModel
    -- clone + camera first (same as the other moves), THEN orbit
    if not ghostModel then
        local char = getCharacter()
        if char and buildGhost(char, ghostWorldCF) then
            local cameraReady = saveAndSetGhostCamera()
            setRealBodyHidden(char, cameraReady)
        else
            ghostBuildRetryAt = os.clock() + 0.25
        end
    else
        pivotGhostRootTo(ghostWorldCF)
        saveAndSetGhostCamera()
    end
    f.active, f.startedAt, f.sweepStart = true, os.clock(), nil
    orbitEnabled = true
    AV.setEnabled(true)
    diagnosticLastHandledTrack = nil
    diagnosticStatus = "Fling armed"
    diagnosticLastOutcome = "Fling: orbit enabled"
    CONFIG.FAILSAFE.deadline = nil -- no watched animation is expected for Fling
end
CONFIG.FLING.start = function()
    local f = CONFIG.FLING
    if not animReady or f.active or CONFIG.FLOW.active or orbitEnabled or animationVoidTrip then return end
    if ov == "shoot1" or ov == "flowing" or ov == "fling" then return end
    if ov == "taunt" then stopTrack(trk.taunt, 0.1) end
    if trk.fling then
        ov = "fling"
        playTrack(trk.fling, 0.05, 0, 1)
    end
    if f.isValidId(f.SOUND_ID) then playSound(tostring(f.SOUND_ID):match("%d+"), animHrp) end
    local targetModel = CONFIG.FLOW.getClosestTargetToCursor(CONFIG.AIM_FOV_FLING)
    if targetModel then f.trigger(targetModel) end
end

------------------------------------------------------------------
-- MODEL BUILD / COLOURS
------------------------------------------------------------------
local function removeModel()
    if model then model:Destroy() model = nil end
    root, muzzleZone = nil, nil
    segments, muzzleParts, muzzleSeq, muzzleLights = {}, {}, {}, {}
end
local function applyMuzzle()
    local c = live.muzzle
    for _, part in ipairs(muzzleParts) do part.Color = c end
    for _, emitter in ipairs(muzzleSeq) do emitter.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.3), c) end
    for _, light in ipairs(muzzleLights) do light.Color = c end
end
local function refreshColor(slot)
    if rainbow[slot] then
        local offset = slot == "muzzle" and 0.5 or 0
        live[slot] = Color3.fromHSV((rainbowPhase + offset) % 1, 0.9, 1)
    else
        live[slot] = colors[slot]
    end
    if slot == "muzzle" then applyMuzzle() end
    if previews[slot] then previews[slot].BackgroundColor3 = live[slot] end
end

local function part(shape, size, cf, color, material, transparency)
    local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    p.Size = size * SC
    p.CFrame = CFrame.new(x * SC, y * SC, z * SC, r00, r01, r02, r10, r11, r12, r20, r21, r22)
    p.Color = color
    p.Material = material or M.SmoothPlastic
    p.Transparency = transparency or 0
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Massless = true
    if shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder
    elseif shape == "Ball" then p.Shape = Enum.PartType.Ball end
    p.Parent = model
    return p
end
local function zcyl(len, dia, x, y, z, color, material)
    return part("Cylinder", Vector3.new(len, dia, dia), CFrame.new(x, y, z) * ZAXIS, color, material)
end
local function blk(sx, sy, sz, x, y, z, color, material)
    return part("Block", Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, material)
end
local function glowEmitter(zone, options)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = options.tex
    emitter.Rate = options.rate
    emitter.Lifetime = NumberRange.new(options.life[1], options.life[2])
    emitter.Speed = NumberRange.new(options.speed[1] * SC, options.speed[2] * SC)
    emitter.SpreadAngle = Vector2.new(options.spread, options.spread)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, options.s0 * SC),
        NumberSequenceKeypoint.new(0.4, options.s1 * SC),
        NumberSequenceKeypoint.new(1, options.s2 * SC),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.15, options.t0),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.LightEmission = 1
    emitter.LightInfluence = 0
    emitter.Acceleration = Vector3.new(0, options.rise or 0, 0)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.RotSpeed = NumberRange.new(-options.rot, options.rot)
    emitter.LockedToPart = options.locked or false
    emitter.Parent = zone
    table.insert(muzzleSeq, emitter)
    return emitter
end

local function findRig()
    local char = player.Character
    if not char then return nil, "no character" end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local arm = char:FindFirstChild("Right Arm")
    local torso = char:FindFirstChild("Torso")
    local shoulder = torso and torso:FindFirstChild("Right Shoulder")
    if not (hum and hum.RigType == Enum.HumanoidRigType.R6 and arm and torso and shoulder) then
        return nil, "this needs an R6 character"
    end
    return { char = char, arm = arm, torso = torso, shoulder = shoulder, hum = hum,
        hrp = char:FindFirstChild("HumanoidRootPart") }
end

------------------------------------------------------------------
-- MODE GUNS: Lightning Cannon -> railgun, Echo -> rusted gun, Immortality Lord -> sword
-- While a mode with  gun = "..."  (see CONFIG.MODES.list) is selected, the revolver is hidden and
-- that gun is held instead. The revolver's muzzle effects + shot origin move to the new gun's tip.
-- (kept inside do...end so it doesn't use up top-level local slots)
------------------------------------------------------------------
CONFIG.GUNS = {
    ---------------- RAILGUN SETTINGS (Lightning Cannon mode) ----------------
    RAILGUN_SCALE = 0.9,            -- size of the railgun (1 = original mesh size, 0.5 = half)
    RAILGUN_HOLD = Vector3.new(0.3, -0.4, 0), -- where the hand holds it, studs at scale 1 from the middle of the handle:
                                    --   X = toward the barrel, Y = up, Z = toward the gun's right side
    RAILGUN_IDLE_FLIP = true,       -- upside down while idle (back to normal when you use a move or a replaced animation plays)
    RAILGUN_IDLE_FACE_BACK = true,  -- barrel points backwards (behind you) in idle instead of forwards
    RAILGUN_IDLE_TILT = 260,        -- degrees the barrel is raised in idle (negative = lowered, 0 = level)
    RAILGUN_POSE_WHILE_WALKING = true, -- false = idle pose only while standing still
    RAILGUN_TUNE = false,           -- true = J/L I/K U/O (Shift = big steps) move the grip live and print RAILGUN_HOLD
    ---------------------------------------------------------------------------
    ---------------- SWORD SETTINGS (Immortality Lord mode) ----------------
    -- The sword is the MeshPart from Studio. Sword axes: Y runs along the blade, X / Z are its width / thickness.
    SWORD_SCALE = 0.7,                -- size of the sword (1 = exactly the size it has in Studio, 0.5 = half)
    SWORD_ROTATION = Vector3.new(285, 0, 0), -- degrees, around your hand, on top of "blade points forward":
                                    --   X = tip up / down, Y = tip left / right, Z = roll the blade around its own length
    SWORD_HOLD = Vector3.new(0, -6, 0),    -- the point on the sword that sits in your hand, studs from the sword's middle (at scale 1)
                                    --   Y = along the blade (negative = toward the handle end), X / Z = sideways
    SWORD_TIP = Vector3.new(0, 8.65, 0),   -- where shots / muzzle effects come out (studs from the sword's middle, at scale 1; the blade tip)
    SWORD_COLOR = Color3.fromRGB(0, 0, 0),
    SWORD_MATERIAL = Enum.Material.Slate,
    ---------------------------------------------------------------------------
    skins = {}, revolverParts = {}, token = 0, zoneOffset = nil, muzzleState = nil, defs = {},
}
do
    local Guns = CONFIG.GUNS
    local AssetService = game:GetService("AssetService")

    ----------------------------------------------------------------
    -- railgun (the lightning cannon: stock + barrel meshes)
    ----------------------------------------------------------------
    Guns.defs.railgun = {
        facing = CFrame.Angles(0, math.pi, 0),
        pose = true, -- idle pose (upside down + tilt) applies to this gun
        make = function(def)
            local s = Guns.RAILGUN_SCALE
            local TEXTURE = "rbxassetid://74471954115673"
            local HANDLE_MESH, HANDLE_SIZE = "rbxassetid://76443789550926", Vector3.new(5.174, 2.958, 1.18)
            local BARREL_MESH, BARREL_SIZE = "rbxassetid://77229698901212", Vector3.new(6.454, 1.394, 1.48)
            local STOCK_GAP, STOCK_Y_OFFSET = -0.55, -0.22
            local gunCF = CFrame.Angles(math.rad(45), 0, 0) * CFrame.new(0, 0, 0, 0, 0, -1, 0.70711, 0.70711, 0, 0.70711, -0.70711, 0)
            local total = HANDLE_SIZE.X + BARREL_SIZE.X + STOCK_GAP
            local stockX = -total / 2 + HANDLE_SIZE.X / 2
            local barrelX = total / 2 - BARREL_SIZE.X / 2
            local stockCF = gunCF * CFrame.new(stockX * s, STOCK_Y_OFFSET * s, 0)
            local barrelCF = gunCF * CFrame.new(barrelX * s, 0, 0)

            local function mesh(name, id, size, cf)
                local piece
                local ok, result = pcall(function() return AssetService:CreateMeshPartAsync(id) end)
                if ok and result then
                    piece = result
                    piece.TextureID = TEXTURE
                else
                    warn(("[PulseRevolver] railgun mesh %s failed to load (%s), using a SpecialMesh instead"):format(name, tostring(result)))
                    piece = Instance.new("Part")
                    local sm = Instance.new("SpecialMesh")
                    sm.MeshType = Enum.MeshType.FileMesh
                    sm.MeshId = id
                    sm.TextureId = TEXTURE
                    sm.Scale = Vector3.new(s, s, s)
                    sm.Parent = piece
                end
                piece.Name = name
                piece.Size = size * s
                piece.Color = Color3.fromRGB(163, 162, 165)
                piece.Material = Enum.Material.Plastic
                return { piece = piece, cf = cf }
            end

            local items = { mesh("RailgunStock", HANDLE_MESH, HANDLE_SIZE, stockCF), mesh("RailgunBarrel", BARREL_MESH, BARREL_SIZE, barrelCF) }
            local h = Guns.RAILGUN_HOLD
            local holdLocal = stockCF.Position + Vector3.new(-h.Z, h.Y, h.X) * s
            local tipLocal = (barrelCF * CFrame.new(BARREL_SIZE.X / 2 * s, 0, 0)).Position
            return items, holdLocal, tipLocal
        end,
    }

    ----------------------------------------------------------------
    -- sword (ImmortalityLord Sword: the single MeshPart copied from Studio)
    ----------------------------------------------------------------
    Guns.defs.sword = {
        -- base turn: the blade (+Y) points forward, then SWORD_ROTATION is added around the hand
        facing = CFrame.Angles(math.rad(Guns.SWORD_ROTATION.X), math.rad(Guns.SWORD_ROTATION.Y), math.rad(Guns.SWORD_ROTATION.Z))
            * CFrame.Angles(math.rad(-90), 0, 0),
        pose = false, -- no idle flip / tilt for the sword
        hideMuzzleGlow = true, -- no particles / light at the blade tip
        make = function(def)
            local s = Guns.SWORD_SCALE
            local MESH = "rbxassetid://1996456880"
            local SIZE = Vector3.new(1.561288, 17.2945213, 4.77217197)          -- Size of the part in Studio
            local INITIAL = Vector3.new(0.390322, 3.57363009, 1.19304299)       -- InitialSize (the mesh's own size)
            local piece
            local ok, result = pcall(function() return AssetService:CreateMeshPartAsync(MESH) end)
            if ok and result then
                piece = result
                piece.TextureID = "" -- the Studio part has no texture
            else
                warn(("[PulseRevolver] sword mesh failed to load (%s), using a SpecialMesh instead"):format(tostring(result)))
                piece = Instance.new("Part")
                local sm = Instance.new("SpecialMesh")
                sm.MeshType = Enum.MeshType.FileMesh
                sm.MeshId = MESH
                sm.Scale = (SIZE / INITIAL) * s
                sm.Parent = piece
            end
            piece.Name = "ImmortalitySword"
            piece.Size = SIZE * s
            piece.Color = Guns.SWORD_COLOR
            piece.Material = Guns.SWORD_MATERIAL
            return { { piece = piece, cf = CFrame.new() } }, Guns.SWORD_HOLD * s, Guns.SWORD_TIP * s
        end,
    }

    ----------------------------------------------------------------
    -- rusted gun (rebuilt 1:1 from plain parts, no union meshes)
    --   row = group, shape, size, CFrame   |  B = rust body, N = red neon, P = diamond plate
    --   shape: B = block, C = cylinder, S = ball, W = wedge
    ----------------------------------------------------------------
    local RUST_PARTS = {
        {"B","W",{0.530002,0.1325,0.265001},{68.861381,10.48754,-3.979074,0,-1,0,0,0,1,-1,0,0}},
        {"P","C",{0.440865,0.432221,0.432221},{69.08641,11.583693,-2.944415,1,0,0,0,-0.052346,0.998629,0,-0.998629,-0.052346}},
        {"P","B",{0.432865,0.487487,0.432221},{69.08641,11.519602,-3.159902,1,0,0,0,-0.23863,0.97111,0,-0.97111,-0.238631}},
        {"P","C",{0.440865,0.432221,0.432221},{69.08641,11.44951,-3.43504,1,0,0,0,-0.052346,0.998629,0,-0.998629,-0.052346}},
        {"N","C",{0.59,0.3225,0.3225},{69.078598,8.891603,-4.174619,0,0,-1,1,0,0,0,-1,0}},
        {"N","C",{1.671999,0.3225,0.3225},{69.078598,8.633791,-4.174619,0,0,-1,1,0,0,0,-1,0}},
        {"N","C",{2.669999,0.3225,0.3225},{69.078598,8.141603,-4.174619,0,0,-1,1,0,0,0,-1,0}},
        {"B","W",{0.144824,0.252159,0.687707},{69.086655,10.823399,-3.855912,1,0,0,0,-1,0,0,0,-1}},
        {"B","W",{0.152824,0.343853,0.947506},{69.086655,10.849378,-3.744507,1,0,0,0,-0.965926,0.258819,0,-0.258819,-0.965926}},
        {"B","W",{0.530002,0.1325,0.265001},{69.321396,10.93754,-3.979067,0,1,0,0,0,1,1,0,0}},
        {"B","W",{0.6,0.2,2},{68.551384,10.14754,-3.979067,0,-0.866025,0.5,0,-0.5,-0.866025,1,0,0}},
        {"N","B",{0.33,0.48,1.52},{69.078598,11.111607,-3.994205,1,0,0,0,0,1,0,-1,0}},
        {"N","C",{0.27,0.3225,0.3225},{69.078598,9.046602,-4.174205,0,0,-1,1,0,0,0,-1,0}},
        {"B","W",{0.399983,0.399849,1.1},{69.081383,11.785288,-3.221475,1,0,0,0,1,0,0,0,1}},
        {"B","W",{0.530002,0.1325,0.265001},{69.321388,10.48754,-3.979067,0,1,0,0,0,1,1,0,0}},
        {"B","C",{3.089999,0.271135,0.271135},{69.086372,7.487541,-4.191474,0,0,1,-1,0,0,0,-1,0}},
        {"B","W",{0.18,0.06,0.600001},{68.901367,7.341321,-4.198266,0,-0.965926,0.258819,0,-0.258819,-0.965926,1,0,0}},
        {"B","C",{0.4,0.4,0.4},{69.08139,11.907539,-3.979067,0,0,1,0,1,0,-1,0,0}},
        {"B","W",{0.1,0.3,0.8},{69.364227,5.99754,-4.451915,0.707107,0.707107,0,0,0,1,0.707107,-0.707107,0}},
        {"B","W",{0.1,0.3,0.8},{68.798531,5.99754,-3.886224,-0.707107,-0.707107,0,0,0,1,-0.707107,0.707107,0}},
        {"B","B",{0.57,0.16,0.06},{68.971382,11.567539,-4.350067,0,0,1,-1,0,0,0,-1,0}},
        {"B","S",{0.4,0.4,0.4},{69.08139,12.00754,-3.789067,1,0,0,0,0,1,0,-1,0}},
        {"B","S",{0.456,0.456,0.456},{69.086365,6.47754,-4.191474,1,0,0,0,0,1,0,-1,0}},
        {"B","W",{0.18,0.06,0.600001},{69.27137,7.351321,-4.189762,0,0.965926,-0.258819,0,-0.258819,-0.965926,-1,0,0}},
        {"B","B",{0.4,0.392,2.692},{69.081367,10.55755,-3.979067,1,0,0,0,0,1,0,-1,0}},
        {"B","B",{0.57,0.16,0.06},{69.191391,11.567539,-4.350317,0,0,1,-1,0,0,0,-1,0}},
        {"B","W",{0.530002,0.1325,0.265001},{68.861381,11.527538,-3.979074,0,-1,0,0,0,1,-1,0,0}},
        {"B","B",{0.391983,1.092,0.599774},{69.081367,11.485387,-3.221475,1,0,0,0,0,1,0,-1,0}},
        {"B","W",{0.530002,0.1325,0.265001},{69.321388,11.527539,-3.979067,0,1,0,0,0,1,1,0,0}},
        {"B","W",{0.399983,0.199925,1.1},{69.081367,11.185503,-3.221475,1,0,0,0,-1,0,0,0,-1}},
        {"B","W",{0.2,0.4,1},{69.08139,10.55754,-4.499067,-1,0,0,0,0,-1,0,-1,0}},
        {"B","C",{2.82,0.4,0.4},{69.08139,10.617539,-3.789067,0,0,1,-1,0,0,0,-1,0}},
        {"B","W",{0.1,0.3,0.8},{68.798538,5.99754,-4.451911,0.707107,-0.707107,0,0,0,1,-0.707107,-0.707107,0}},
        {"B","S",{0.4,0.4,0.4},{69.08139,9.207541,-3.789103,1,0,0,0,0,1,0,-1,0}},
        {"B","C",{1.46,0.2,0.2},{69.08139,8.489563,-3.974654,0,0,1,-0.965926,0.258819,0,-0.258819,-0.965926,0}},
        {"B","S",{0.6,0.6,0.6},{69.08139,6.487538,-4.179067,1,0,0,0,0,1,0,-1,0}},
        {"B","C",{2.7,0.35,0.35},{69.08139,7.777541,-4.179067,0,0,1,-1,0,0,0,-1,0}},
        {"B","W",{0.2,0.4,0.2},{69.08139,9.957541,-4.499067,1,0,0,0,0,1,0,-1,0}},
        {"B","W",{0.1,0.3,0.8},{69.364227,5.99754,-3.886225,-0.707107,0.707107,0,0,0,1,0.707107,0.707107,0}},
        {"B","C",{0.39,0.4,0.4},{69.08139,11.955364,-3.980489,0,-1,0,-0.258819,0,0.965926,-0.965926,0,-0.258819}},
        {"B","W",{0.592,0.2,2},{69.621368,10.14754,-3.979067,0,0.866025,-0.5,0,-0.5,-0.866025,-1,0,0}},
        {"B","C",{1,0.6,0.6},{69.08139,5.997542,-4.179067,0,0,1,-1,0,0,0,-1,0}},
        {"B","C",{2.7,0.4,0.4},{69.08139,10.55754,-4.179067,0,0,1,-1,0,0,0,-1,0}},
        {"B","S",{0.4,0.4,0.4},{69.08139,11.907539,-4.179067,1,0,0,0,0,1,0,-1,0}},
        {"B","C",{0.4,0.4,0.4},{69.08139,9.20754,-3.979067,0,0,1,0,1,0,-1,0,0}},
        {"B","W",{0.2,0.2,1.4},{69.08139,8.01754,-4.409067,1,0,0,0,0,1,0,-1,0}},
        {"B","S",{0.4,0.4,0.4},{69.08139,9.207541,-4.179067,1,0,0,0,0,1,0,-1,0}},
        {"B","W",{0.530002,0.1325,0.265001},{68.861374,10.93754,-3.979076,0,-1,0,0,0,1,-1,0,0}},
    }
    Guns.defs.rust = {
        scale = 0.75,                          -- size of the rusted gun in your hand (1 = original size)
        holdFile = Vector3.new(0, 2.2, -0.2),  -- the point on the gun that sits in your hand (studs from the gun's middle, original size)
        tipFile = Vector3.new(0, -3.355, -0.5),-- where shots / muzzle effects come out (the bottom end where the old Hole marker was)
        facing = CFrame.Angles(math.rad(90), 0, 0), -- bottom end points forward, neon side faces up
        make = function(def)
            local s = def.scale
            local groups = {
                B = { material = Enum.Material.CorrodedMetal, color = Color3.fromRGB(86, 36, 36) },
                N = { material = Enum.Material.Neon,          color = Color3.fromRGB(255, 0, 0) },
                P = { material = Enum.Material.DiamondPlate,  color = Color3.fromRGB(99, 95, 98) },
            }
            local shapes = { B = Enum.PartType.Block, C = Enum.PartType.Cylinder, S = Enum.PartType.Ball }
            local center = Vector3.new(69.0864105, 8.85254097, -3.68017197)
            local items = {}
            for i, d in ipairs(RUST_PARTS) do
                local g = groups[d[1]]
                local piece
                if d[2] == "W" then
                    piece = Instance.new("WedgePart")
                else
                    piece = Instance.new("Part")
                    piece.Shape = shapes[d[2]]
                end
                piece.Name = "Rust" .. d[1] .. i
                piece.Size = Vector3.new(unpack(d[3])) * s
                piece.Color = g.color
                piece.Material = g.material
                local rel = CFrame.new(unpack(d[4])) - center
                table.insert(items, { piece = piece, cf = CFrame.new(rel.Position * s) * (rel - rel.Position) })
            end
            return items, def.holdFile * s, def.tipFile * s
        end,
    }

    ----------------------------------------------------------------
    -- attach / show / hide / pose
    ----------------------------------------------------------------
    local function moveMuzzle(part0, offsetCF, state)
        local zone = muzzleZone
        if not (zone and root and zone.Parent) or Guns.muzzleState == state then return end
        Guns.muzzleState = state
        local oldWeld = zone:FindFirstChildOfClass("WeldConstraint")
        if oldWeld then oldWeld:Destroy() end
        zone.CFrame = part0.CFrame * offsetCF
        local weld = Instance.new("WeldConstraint")
        weld.Part0, weld.Part1 = part0, zone
        weld.Parent = zone
    end

    -- (re)place a gun's parts around its pivot (the pivot sits in the hand; the gun is rotated around it)
    local function placeSkin(skin, def)
        local base = def.facing * CFrame.new(-skin.holdLocal)
        for _, it in ipairs(skin.items) do
            local piece = it.piece
            local old = piece:FindFirstChildOfClass("WeldConstraint")
            if old then old:Destroy() end
            piece.CFrame = skin.pivot.CFrame * (base * it.cf)
            if not piece.Parent then piece.Parent = skin.pivot.Parent end
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1 = skin.pivot, piece
            weld.Parent = piece
        end
        skin.tip = base:PointToWorldSpace(skin.tipLocal) -- relative to the pivot
        Guns.muzzleState = nil
    end

    -- hide the revolver + show the gun of the current mode (or the revolver if the mode has no gun)
    Guns.refresh = function()
        if not model or not root then return end
        local mode = CONFIG.MODES.list[CONFIG.MODES.index]
        local active = mode and mode.gun
        local skin = active and Guns.skins[active]
        if not (skin and skin.ready) then active, skin = nil, nil end
        for p, original in pairs(Guns.revolverParts) do
            if p.Parent then p.Transparency = skin and 1 or original end
        end
        for name, s in pairs(Guns.skins) do
            for p, original in pairs(s.parts) do
                if p.Parent then p.Transparency = (name == active) and original or 1 end
            end
        end
        if skin and skin.tip then
            moveMuzzle(skin.pivot, CFrame.new(skin.tip), active)
        elseif Guns.zoneOffset then
            moveMuzzle(root, Guns.zoneOffset, "revolver")
        end
        -- some guns (the sword) have no glow at the tip: switch the muzzle particles + light off
        local activeDef = active and Guns.defs[active]
        local hideGlow = activeDef ~= nil and activeDef.hideMuzzleGlow == true
        for _, emitter in ipairs(muzzleSeq) do
            if emitter.Parent then
                if hideGlow then emitter:Clear() end
                emitter.Enabled = not hideGlow
            end
        end
        for _, light in ipairs(muzzleLights) do
            if light.Parent then light.Enabled = not hideGlow end
        end
    end

    -- every frame: upside down + tilted while idle, normal while a move is being used
    Guns.step = function(dt)
        for name, skin in pairs(Guns.skins) do
            local def = Guns.defs[name]
            if def and def.pose and skin.ready and skin.motor and skin.motor.Parent then
                local mode = CONFIG.MODES.list[CONFIG.MODES.index]
                local performing = ov ~= nil or CONFIG.FLOW.active
                if not performing then -- a replaced animation (e.g. Lightning Cannon's) counts as a move too
                    for _, track in pairs(CONFIG.REPLACE.tracks) do
                        if track.IsPlaying then performing = true break end
                    end
                end
                local walking = stillTime <= 0
                local idle = mode and mode.gun == name and not performing and (Guns.RAILGUN_POSE_WHILE_WALKING or not walking)
                local pose = idle and 1 or 0 -- instant: no rotating with a speed
                if pose ~= skin.lastPose then
                    skin.pose, skin.lastPose = pose, pose
                    local k = pose
                    local rot = CFrame.Angles(0, Guns.RAILGUN_IDLE_FACE_BACK and math.pi * k or 0, 0)
                        * CFrame.Angles(math.rad(Guns.RAILGUN_IDLE_TILT) * k, 0, 0)
                        * CFrame.Angles(0, 0, Guns.RAILGUN_IDLE_FLIP and math.pi * k or 0)
                    skin.motor.C1 = rot:Inverse() -- pivot = root * C0 * rot (turns around the hand)
                end
            end
        end
    end

    -- called at the end of build(): remembers the revolver parts and builds every gun next to them
    Guns.attachAll = function()
        Guns.token += 1
        local token = Guns.token
        Guns.skins, Guns.revolverParts, Guns.muzzleState = {}, {}, nil
        local thisModel, thisRoot, thisZone = model, root, muzzleZone
        for _, p in ipairs(thisModel:GetDescendants()) do
            if p:IsA("BasePart") and p ~= thisRoot and p ~= thisZone then Guns.revolverParts[p] = p.Transparency end
        end
        Guns.zoneOffset = thisZone and thisRoot.CFrame:ToObjectSpace(thisZone.CFrame) or nil

        for name, def in pairs(Guns.defs) do
            local skin = { parts = {}, ready = false, tip = nil, pose = 0 }
            Guns.skins[name] = skin
            task.spawn(function()
                local ok, items, holdLocal, tipLocal = pcall(def.make, def)
                if not ok then warn("[PulseRevolver] gun '" .. name .. "' failed: " .. tostring(items)) return end
                if token ~= Guns.token or not thisModel.Parent then
                    for _, it in ipairs(items) do it.piece:Destroy() end
                    return
                end
                -- pivot = invisible part in the hand; a Motor6D lets us turn the whole gun around it
                local grip = CFrame.new(CONFIG.GRIP_POINT * SC)
                local pivot = Instance.new("Part")
                pivot.Name = "GunPivot_" .. name
                pivot.Size = Vector3.new(0.2, 0.2, 0.2)
                pivot.Transparency = 1
                pivot.Anchored = false
                pivot.CanCollide, pivot.CanTouch, pivot.CanQuery = false, false, false
                pivot.Massless = true
                pivot.CFrame = thisRoot.CFrame * grip
                pivot.Parent = thisModel
                local motor = Instance.new("Motor6D")
                motor.Name = "GunPivotMotor"
                motor.Part0, motor.Part1 = thisRoot, pivot
                motor.C0, motor.C1 = grip, CFrame.new()
                motor.Parent = pivot
                skin.pivot, skin.motor, skin.items, skin.holdLocal, skin.tipLocal = pivot, motor, items, holdLocal, tipLocal

                for _, it in ipairs(items) do
                    local piece = it.piece
                    piece.Anchored = false
                    piece.CanCollide = false
                    piece.CanTouch = false
                    piece.CanQuery = false
                    piece.CastShadow = false
                    piece.Massless = true
                    piece.Transparency = 1
                    skin.parts[piece] = it.transparency or 0
                end
                placeSkin(skin, def)
                skin.ready = true
                Guns.refresh()
            end)
        end
        Guns.refresh()
    end

    ----------------------------------------------------------------
    -- optional live tuning of the railgun grip (RAILGUN_TUNE = true)
    ----------------------------------------------------------------
    if Guns.RAILGUN_TUNE then
        UserInputService.InputBegan:Connect(function(input, processed)
            if processed or deleted then return end
            local skin, def = Guns.skins.railgun, Guns.defs.railgun
            if not (skin and skin.ready) then return end
            local step = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 0.25 or 0.05
            local k, d = input.KeyCode, nil
            if k == Enum.KeyCode.L then d = Vector3.new(step, 0, 0)       -- toward the barrel
            elseif k == Enum.KeyCode.J then d = Vector3.new(-step, 0, 0)
            elseif k == Enum.KeyCode.I then d = Vector3.new(0, step, 0)   -- up
            elseif k == Enum.KeyCode.K then d = Vector3.new(0, -step, 0)
            elseif k == Enum.KeyCode.O then d = Vector3.new(0, 0, step)   -- toward the gun's right
            elseif k == Enum.KeyCode.U then d = Vector3.new(0, 0, -step) end
            if not d then return end
            local h = Guns.RAILGUN_HOLD + d
            Guns.RAILGUN_HOLD = h
            local s = Guns.RAILGUN_SCALE
            skin.holdLocal = skin.holdLocal + Vector3.new(-d.Z, d.Y, d.X) * s
            placeSkin(skin, def)
            Guns.refresh()
            print(("[PulseRevolver] RAILGUN_HOLD = Vector3.new(%.2f, %.2f, %.2f)"):format(h.X, h.Y, h.Z))
        end)
    end
end

local function build(rig)
    removeModel()
    model = Instance.new("Model")
    model.Name = "Pulse Revolver"
    root = Instance.new("Part")
    root.Name = "Handle"
    root.Size = Vector3.new(0.2, 0.2, 0.2)
    root.Transparency = 1
    root.Anchored = true
    root.CanCollide = false
    root.CanTouch = false
    root.CanQuery = false
    root.Massless = true
    root.Parent = model
    model.PrimaryPart = root
    local R, T = 0.475, 0.3
    zcyl(T, R * 2, 0, 0, 0, BLACK, M.SmoothPlastic)
    zcyl(T + 0.04, R * 0.6, 0, 0, 0, BODY, M.Metal)
    local N = CONFIG.PULSE_SEGMENTS
    local tangent = (2 * math.pi * R / N) * 1.2
    for i = 0, N - 1 do
        local a = i / N * math.pi * 2
        local rot = CFrame.Angles(0, 0, a)
        local face = part("Block", Vector3.new(0.07, tangent, 0.05),
            CFrame.new(math.cos(a) * (R - 0.06), math.sin(a) * (R - 0.06), -T / 2 - 0.015) * rot, BLACK, M.Neon)
        local rim = part("Block", Vector3.new(0.05, tangent, T * 0.55),
            CFrame.new(math.cos(a) * (R + 0.01), math.sin(a) * (R + 0.01), 0) * rot, BLACK, M.Neon)
        local group = { face, rim }
        if i % CONFIG.TEETH_EVERY == 0 then
            local tooth = part("Block", Vector3.new(0.12, tangent * 1.5, T * 0.8),
                CFrame.new(math.cos(a) * (R + 0.07), math.sin(a) * (R + 0.07), 0) * rot, BLACK, M.Neon)
            table.insert(group, tooth)
        end
        table.insert(segments, { parts = group, angle = a })
    end
    local necks = { { 0.7, -0.24 }, { 0.54, -0.42 }, { 0.42, -0.6 } }
    for _, n in ipairs(necks) do zcyl(0.19, n[1], 0, 0, n[2], BODY, M.Metal) end
    zcyl(4.4, 0.22, 0, 0, -2.8, BODY, M.Metal)
    zcyl(0.95, 0.42, 0, 0, -2.05, BODY2, M.Metal)
    zcyl(0.1, 0.5, 0, 0, -1.55, BODY, M.Metal)
    zcyl(0.1, 0.5, 0, 0, -2.55, BODY, M.Metal)
    zcyl(0.12, 0.31, 0, 0, -3.5, BODY2, M.Metal)
    zcyl(0.12, 0.31, 0, 0, -4.2, BODY2, M.Metal)
    blk(0.3, 0.22, 0.6, 0, 0, -4.8, BODY2, M.Metal)
    blk(0.08, 0.17, 0.32, 0, 0.19, -4.7, BODY, M.Metal)
    zcyl(0.8, 0.72, 0, 0, 0.55, BODY, M.Metal)
    zcyl(0.07, 0.78, 0, 0, 0.35, BODY2, M.Metal)
    zcyl(0.07, 0.78, 0, 0, 0.65, BODY2, M.Metal)
    zcyl(0.07, 0.78, 0, 0, 0.93, BODY2, M.Metal)
    part("Block", Vector3.new(0.14, 0.42, 0.2), CFrame.new(0, 0.38, 1.0) * CFrame.Angles(0.6, 0, 0), BODY2, M.Metal)
    blk(0.5, 0.75, 1.0, 0, -0.42, 0.62, BODY, M.Metal)
    local gtop = Vector3.new(0, -0.7, 0.95)
    local ang = 0.28
    local gdir = Vector3.new(0, -math.cos(ang), math.sin(ang))
    local gcen = gtop + gdir * 0.85
    part("Block", Vector3.new(0.56, 1.7, 0.72), CFrame.new(gcen) * CFrame.Angles(-ang, 0, 0), BODY, M.SmoothPlastic)
    local gend = gtop + gdir * 1.7
    part("Block", Vector3.new(0.62, 0.12, 0.8), CFrame.new(gend) * CFrame.Angles(-ang, 0, 0), BODY2, M.Metal)
    for k = 1, 4 do
        local gp = gtop + gdir * (0.3 + k * 0.28)
        part("Block", Vector3.new(0.6, 0.05, 0.76), CFrame.new(gp) * CFrame.Angles(-ang, 0, 0), BODY2, M.Metal)
    end
    blk(0.1, 0.07, 0.8, 0, -1.0, 0.45, BODY2, M.Metal)
    blk(0.1, 0.34, 0.08, 0, -0.84, 0.05, BODY2, M.Metal)
    blk(0.08, 0.3, 0.1, 0, -0.68, 0.5, BODY2, M.Metal)
    local zone = part("Block", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0, -5.12), BLACK, M.SmoothPlastic, 1)
    muzzleZone = zone
    glowEmitter(zone, { tex = "rbxasset://textures/particles/smoke_main.dds", rate = 40, life = { 0.3, 0.55 }, speed = { 0, 0.2 }, spread = 40,
        s0 = 0.75, s1 = 0.6, s2 = 0.3, t0 = 0.25, rot = 40, locked = true })
    glowEmitter(zone, { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 14, life = { 0.4, 0.9 }, speed = { 0.5, 1.6 }, spread = 180,
        s0 = 0.22, s1 = 0.16, s2 = 0, t0 = 0.05, rot = 120 })
    glowEmitter(zone, { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 12, life = { 1.0, 1.8 }, speed = { 0.15, 0.6 }, spread = 180,
        s0 = 0.1, s1 = 0.08, s2 = 0, t0 = 0.1, rise = 0.7, rot = 60 })
    local light = Instance.new("PointLight")
    light.Range = 6 * SC
    light.Brightness = 1.2
    light.Shadows = false
    light.Parent = zone
    table.insert(muzzleLights, light)
    applyMuzzle()
    local C1 = CFrame.new(CONFIG.GRIP_POINT * SC)
    model:PivotTo(rig.arm.CFrame * GRIP_C0 * C1:Inverse())
    model.Parent = rig.char
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p ~= root then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = root
            weld.Part1 = p
            weld.Parent = p
        end
    end
    for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
    local grip = Instance.new("Motor6D")
    grip.Name = "PulseRevolverGrip"
    grip.Part0 = rig.arm
    grip.Part1 = root
    grip.C0 = GRIP_C0
    grip.C1 = C1
    grip.Parent = root
    CONFIG.GUNS.attachAll()
end

------------------------------------------------------------------
-- ATTACH / FRAME UPDATE
------------------------------------------------------------------
local function frame(dt)
    dt = math.min(dt, 0.1)
    animStep(dt)
    CONFIG.FX.step(dt)
    CONFIG.GUNS.step(dt)
    rainbowPhase = (rainbowPhase + dt * rainbowSpeed) % 1
    if rainbow.pulse or rainbow.muzzle then
        Perf.rainbowAcc += dt
        if Perf.rainbowAcc >= 1 / 30 then
            Perf.rainbowAcc = 0
            if rainbow.pulse then refreshColor("pulse") end
            if rainbow.muzzle then refreshColor("muzzle") end
        end
    end
    pulsePhase = (pulsePhase + dt * pulseSpeed) % 1
    local head = pulsePhase * math.pi * 2
    local tail = CONFIG.PULSE_TAIL
    Perf.pulseAcc += dt
    if Perf.pulseAcc < 1 / 40 then return end
    Perf.pulseAcc = 0
    local pulseColor = live.pulse
    for _, segment in ipairs(segments) do
        local d = (head - segment.angle) % (math.pi * 2)
        local k = 0
        if d < tail then
            local x = 1 - d / tail
            k = x * x * (3 - 2 * x)
        end
        local color = BLACK
        if k > 0 then
            color = BLACK:Lerp(pulseColor, k)
            if k > 0.85 then color = color:Lerp(Color3.new(1, 1, 1), (k - 0.85) * 1.6) end
        end
        -- most segments sit at black every frame; only touch parts whose colour really changed
        if segment.last ~= color then
            segment.last = color
            for _, p in ipairs(segment.parts) do p.Color = color end
        end
    end
end

local function attach()
    local rig, why = findRig()
    if not rig then warn("[PulseRevolver] " .. tostring(why)) return false end
    build(rig)
    if cooldownDeathConnection then cooldownDeathConnection:Disconnect() cooldownDeathConnection = nil end
    cooldownDeathConnection = rig.hum.Died:Connect(resetToolCooldown)
    if not connection then connection = RunService.RenderStepped:Connect(Perf.wrap("revolverFrame", frame)) end
    setupAnimations(rig)
    return true
end

------------------------------------------------------------------
-- UI HELPERS / PANEL
------------------------------------------------------------------
local function mk(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do object[key] = value end
    object.Parent = parent
    return object
end

-- the old Pulse Revolver panel is gone: colours, text and songs now come from the modes (M).
-- Only a DELETE ALL button is left.
local function buildUI()
    local old = playerGui:FindFirstChild("PulseRevolverPanel")
    if old then old:Destroy() end
    gui = mk("ScreenGui", { Name = "PulseRevolverPanel", ResetOnSpawn = false, DisplayOrder = 100 }, playerGui)
    local deleteButton = mk("TextButton", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.new(0, 140, 0, 30),
        BackgroundColor3 = Color3.fromRGB(170, 30, 30), BorderSizePixel = 0, Font = Enum.Font.Arcade,
        Text = "DELETE ALL", TextSize = 15, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true,
    }, gui)
    deleteButton.MouseButton1Click:Connect(function() deleteAll() end)
end

------------------------------------------------------------------
-- TELEPORT (T) - instant, no cooldown, no animation
------------------------------------------------------------------
local Teleport = { SOUND_ID = 18319185077, FADE_TIME = 0.9, OVAL_SIZE = Vector3.new(5, 9, 5) }

local function teleportEffect(rootPart)
    local tip = live.muzzle
    local function makePart(size, meshType, transparency)
        local p = Instance.new("Part")
        p.Material = M.Neon
        p.Color = tip
        p.Transparency = transparency
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Size = size
        if meshType then
            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType = meshType
            mesh.Parent = p
        end
        p.Parent = workspace
        return p
    end

    local size = Teleport.OVAL_SIZE
    -- outer oval (big, glowing shell), inner core (bright, hot centre)
    local outer = makePart(size, Enum.MeshType.Sphere, 0.25)
    local core = makePart(size * 0.55, Enum.MeshType.Sphere, 0)
    -- ground ring + upward-streaking shell
    local ring = makePart(Vector3.new(0.2, size.X, size.X), nil, 0.2)
    ring.Shape = Enum.PartType.Cylinder
    local shell = makePart(size * 1.25, Enum.MeshType.Sphere, 0.7)

    -- small spark burst
    local attachment = Instance.new("Attachment")
    attachment.Parent = rootPart
    local sparks = Instance.new("ParticleEmitter")
    sparks.Color = ColorSequence.new(tip:Lerp(Color3.new(1, 1, 1), 0.5), tip)
    sparks.LightEmission = 1
    sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
    sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    sparks.Lifetime = NumberRange.new(0.5, 0.9)
    sparks.Speed = NumberRange.new(8, 18)
    sparks.SpreadAngle = Vector2.new(180, 180)
    sparks.Drag = 3
    sparks.Rate = 0
    sparks.Parent = attachment
    sparks:Emit(24)

    local start = os.clock()
    local conn
    local function cleanup()
        if conn then conn:Disconnect() conn = nil end
        outer:Destroy() core:Destroy() ring:Destroy() shell:Destroy()
        task.delay(1, function() if attachment.Parent then attachment:Destroy() end end)
    end
    conn = RunService.Heartbeat:Connect(function()
        local alpha = (os.clock() - start) / Teleport.FADE_TIME
        if alpha >= 1 or not outer.Parent then cleanup() return end
        local cf = rootPart.Parent and rootPart.CFrame or outer.CFrame
        local ease = 1 - (1 - alpha) ^ 2
        local color = live.muzzle
        local hot = color:Lerp(Color3.new(1, 1, 1), 0.6)

        -- outer oval: stays tall, swells a little and fades slowly
        outer.Size = size * (1 + 0.25 * ease)
        outer.CFrame = cf
        outer.Transparency = 0.25 + 0.75 * alpha
        outer.Color = color

        -- core: bright white-hot centre that shrinks and vanishes sooner
        core.Size = size * 0.55 * (1 - 0.6 * ease)
        core.CFrame = cf
        core.Transparency = math.clamp(alpha * 1.8, 0, 1)
        core.Color = hot

        -- faint outer shell expanding faster
        shell.Size = size * (1.25 + 0.6 * ease)
        shell.CFrame = cf
        shell.Transparency = 0.7 + 0.3 * alpha
        shell.Color = color

        -- flat ring on the ground expanding outward
        local groundY = cf.Position.Y - (rootPart.Size.Y / 2) - 1.9
        local d = size.X * (1 + 2.2 * ease)
        ring.Size = Vector3.new(0.2, d, d)
        ring.CFrame = CFrame.new(cf.Position.X, groundY, cf.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
        ring.Transparency = 0.2 + 0.8 * alpha
        ring.Color = color
    end)
end

local function teleportToCursor()
    if deleted then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    -- teleport whatever body we are currently controlling (ghost clone if active, else real character)
    local useGhost = ghostModel ~= nil and ghostRoot ~= nil and ghostRoot.Parent ~= nil
    local char = useGhost and ghostModel or getCharacter()
    local rootPart = useGhost and ghostRoot or getRoot()
    if not char or not rootPart or not rootPart.Parent then return end

    local mouse = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { char, ghostFolder }
    local realChar = player.Character
    if realChar then table.insert(ignore, realChar) end
    if ghostModel then table.insert(ignore, ghostModel) end
    if model then table.insert(ignore, model) end
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
    if not hit then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local lift = rootPart.Size.Y / 2 + (hum and hum.HipHeight or 0) + 0.1
    local destination = hit.Position + Vector3.new(0, lift, 0)
    local newCFrame = CFrame.new(destination) * (rootPart.CFrame - rootPart.CFrame.Position)

    if useGhost then
        pivotGhostRootTo(newCFrame)
    else
        char:PivotTo(newCFrame * rootPart.CFrame:ToObjectSpace(char:GetPivot()))
        rootPart.AssemblyLinearVelocity = Vector3.zero
    end
    playSound(Teleport.SOUND_ID, rootPart)
    teleportEffect(rootPart)
end

------------------------------------------------------------------
-- MOVES BOX (always visible, left-middle, shakes slightly)
-- Title + border use the TIP colour, move lines + status use the CYLINDER colour.
------------------------------------------------------------------
local MovesBox = { gui = nil, conn = nil, tag = nil }

local function buildMovesBox()
    local old = playerGui:FindFirstChild("PulseRevolverMoves")
    if old then old:Destroy() end
    if MovesBox.conn then MovesBox.conn:Disconnect() MovesBox.conn = nil end
    local oldTag = playerGui:FindFirstChild("PulseRevolverNameTag")
    if oldTag then oldTag:Destroy() end
    MovesBox.tag = nil

    local g = mk("ScreenGui", { Name = "PulseRevolverMoves", ResetOnSpawn = false, DisplayOrder = 100, IgnoreGuiInset = true }, playerGui)
    local basePos = UDim2.new(0, 14, 0.5, 0)
    local box = mk("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = basePos, Size = UDim2.new(0, 220, 0, 322),
        BackgroundColor3 = Color3.fromRGB(12, 13, 18), BackgroundTransparency = 0.5, BorderSizePixel = 0,
    }, g)
    local stroke = mk("UIStroke", { Thickness = 2, Color = live.muzzle, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)

    local function line(text, y, h, size, color, align)
        return mk("TextLabel", {
            Position = UDim2.new(0, 10, 0, y), Size = UDim2.new(1, -20, 0, h), BackgroundTransparency = 1,
            Font = Enum.Font.Arcade, Text = text, TextSize = size, TextColor3 = color,
            TextXAlignment = align or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        }, box)
    end

    local title = line("Evo Banisher", 8, 30, 28, live.muzzle)
    title.TextScaled = true -- shrinks the text if needed so "Evo Banisher" always fits the box
    mk("UITextSizeConstraint", { MaxTextSize = 28 }, title)
    MovesBox.title = title
    local moves = {
        line("E - Kill", 42, 26, 22, live.pulse),
        line("R - Bring", 70, 26, 22, live.pulse),
        line("T - Teleport", 98, 26, 22, live.pulse),
        line("Y - Taunt", 126, 26, 22, live.pulse),
        line("V - Fling", 154, 26, 22, live.pulse),
        line("C - Delete", 182, 26, 22, live.pulse),
        line("M - Mode", 210, 26, 22, live.pulse),
        line("P - Kill Mode : " .. CONFIG.ATTACK.mode(), 238, 26, 22, live.pulse),
        line("L - Bring Mode : " .. CONFIG.BRING.modes[CONFIG.BRING.index], 266, 26, 22, live.pulse),
    }
    for i = 8, 9 do -- the longer lines shrink to fit the box
        moves[i].TextScaled = true
        mk("UITextSizeConstraint", { MaxTextSize = 22 }, moves[i])
    end
    MovesBox.attackLine, MovesBox.bringLine = moves[8], moves[9]
    MovesBox.moves = moves
    local status = line("STATUS - ALIVE", 296, 18, 14, live.pulse, Enum.TextXAlignment.Right)

    local function motion(label, rs, rp, ra, xs, xp, ys, yp, amp)
        return { label = label, base = label.Position, rs = rs, rp = rp, ra = ra, xs = xs, xp = xp, ys = ys, yp = yp, amp = amp }
    end
    local motionLabels = {
        motion(title,    1.6, 0.0, 1.4, 2.3, 0.4, 1.9, 2.0, 1.5),
        motion(moves[1], 2.2, 1.7, 1.0, 1.4, 3.1, 2.6, 0.7, 1.2),
        motion(moves[2], 1.1, 3.3, 1.8, 2.8, 1.2, 1.3, 4.1, 1.8),
        motion(moves[3], 2.7, 5.0, 1.2, 1.8, 5.2, 2.4, 2.9, 1.4),
        motion(moves[4], 1.4, 0.9, 1.5, 2.0, 2.2, 1.2, 5.0, 1.3),
        motion(moves[5], 2.4, 4.2, 1.1, 1.5, 0.3, 2.2, 3.4, 1.6),
        motion(moves[6], 1.7, 2.6, 1.3, 2.1, 4.4, 1.7, 1.9, 1.4),
        motion(moves[7], 2.0, 3.9, 1.2, 1.6, 0.8, 2.3, 4.7, 1.5),
        motion(moves[8], 1.3, 1.4, 1.1, 2.2, 2.7, 1.5, 3.3, 1.3),
        motion(moves[9], 2.1, 4.8, 1.4, 1.7, 1.9, 2.0, 0.6, 1.4),
        motion(status,   1.9, 2.4, 0.9, 2.5, 0.9, 1.6, 3.6, 1.0),
    }

    MovesBox.gui = g

    -- "Evo Banisher" name tag floating above the head (cylinder colour, Arcade font, sways left/right)
    local tag = mk("BillboardGui", {
        Name = "PulseRevolverNameTag", Size = UDim2.fromOffset(320, 40), StudsOffset = Vector3.new(0, 2.4, 0),
        AlwaysOnTop = true, LightInfluence = 0, ResetOnSpawn = false,
    }, playerGui)
    local tagBase = UDim2.fromScale(0.5, 0.5)
    local tagLabel = mk("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = tagBase, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Font = Enum.Font.Arcade, Text = "Evo Banisher", TextSize = 26, TextScaled = true, TextColor3 = live.pulse,
        TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.5,
    }, tag)
    mk("UITextSizeConstraint", { MaxTextSize = 26 }, tagLabel)
    MovesBox.tag = tag
    MovesBox.tagLabel = tagLabel
    local lastAdornee, lastTagColor = nil, nil
    -- GUI motion is slow and tiny, so it only needs ~30 updates/s; property writes only on change.
    local accum, lastTip, lastCyl, lastStatus = 1, nil, nil, nil
    MovesBox.conn = RunService.RenderStepped:Connect(Perf.wrap("movesBox", function(dt)
        if deleted or not box.Parent then return end
        -- name tag sway runs every frame so the wider left/right motion stays smooth
        local ts = os.clock()
        tagLabel.Position = tagBase + UDim2.fromOffset(math.sin(ts * 1.9) * 7, math.cos(ts * 1.3) * 1.5)
        tagLabel.Rotation = math.sin(ts * 1.6) * 2
        accum += dt
        if accum < 1 / 30 then return end
        accum = 0
        local tip, cyl = live.muzzle, live.pulse
        if tip ~= lastTip then
            lastTip = tip
            stroke.Color = tip
            title.TextColor3 = tip
            CONFIG.MODES.contrast(title, tip, 1, BLACK)
        end
        if cyl ~= lastCyl then
            lastCyl = cyl
            for _, l in ipairs(moves) do
                l.TextColor3 = cyl
                CONFIG.MODES.contrast(l, cyl, 1, BLACK)
            end
            status.TextColor3 = cyl
            CONFIG.MODES.contrast(status, cyl, 1, BLACK)
        end
        -- name tag: follow the ghost head while ghosting, otherwise the real head; colour = cylinder colour
        local adornee
        if ghostModel and ghostHead and ghostHead.Parent then
            adornee = ghostHead
        else
            local ch = getCharacter()
            adornee = ch and ch:FindFirstChild("Head")
        end
        if adornee ~= lastAdornee then
            lastAdornee = adornee
            tag.Adornee = adornee
        end
        if cyl ~= lastTagColor then
            lastTagColor = cyl
            tagLabel.TextColor3 = cyl
            CONFIG.MODES.contrast(tagLabel, cyl, 0.5, BLACK)
        end
        local hum = getHumanoid()
        local statusText = (hum and hum.Health > 0) and "STATUS - ALIVE" or "STATUS - DEAD"
        if statusText ~= lastStatus then
            lastStatus = statusText
            status.Text = statusText
        end
        -- slow, gentle motion. Box and every text line each use their own speeds/phases.
        local t = os.clock()
        box.Rotation = math.sin(t * 1.3) * 0.5 + math.sin(t * 2.1 + 1) * 0.25
        box.Position = basePos + UDim2.fromOffset(math.sin(t * 1.7) * 1, math.cos(t * 1.1) * 1)
        for _, m in ipairs(motionLabels) do
            m.label.Rotation = math.sin(t * m.rs + m.rp) * m.ra
            m.label.Position = m.base + UDim2.fromOffset(math.sin(t * m.xs + m.xp) * m.amp, math.cos(t * m.ys + m.yp) * m.amp)
        end
    end))
end

------------------------------------------------------------------
-- THEME MUSIC (readfile / writefile / getcustomasset)
-- Settings live in CONFIG.THEME. At runtime you can also call CONFIG.THEME.setVolume(0.3).
------------------------------------------------------------------
CONFIG.THEME.findFile = function()
    local T = CONFIG.THEME
    if isfile(T.FILE) then return T.FILE, {} end
    -- not at the exact path: look through the workspace (root + subfolders) for a close match
    local audio = {}
    if type(listfiles) ~= "function" then return nil, audio end
    local wantName = string.lower(T.FILE)
    local wantStem = (string.gsub(wantName, "%.%w+$", ""))
    local found = nil
    local function scan(folder, depth)
        local ok, list = pcall(listfiles, folder)
        if not ok or type(list) ~= "table" then return false end
        for _, path in ipairs(list) do
            local name = string.lower(string.match(path, "[^/\\]+$") or path)
            if type(isfolder) == "function" and isfolder(path) then
                if depth < 3 then scan(path, depth + 1) end
            elseif string.match(name, "%.mp3$") or string.match(name, "%.ogg$") or string.match(name, "%.wav$") or string.match(name, "%.mp3%.") then
                table.insert(audio, path)
                if not found and (name == wantName or string.find(name, wantStem, 1, true)) then found = path end
            end
        end
        return #list > 0
    end
    if not scan(".", 0) then scan("", 0) end
    return found, audio
end

CONFIG.THEME.getAsset = function()
    local T = CONFIG.THEME
    local assetFn = (type(getcustomasset) == "function" and getcustomasset) or (type(getsynasset) == "function" and getsynasset) or nil
    if not (type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function" and assetFn) then
        warn("[PulseRevolver][theme] your executor does not support isfile/readfile/writefile/getcustomasset - theme music skipped")
        return nil
    end
    local path, audio = T.findFile()
    if not path and T.URL ~= "" then
        local okGet, data = pcall(function() return game:HttpGet(T.URL) end)
        if okGet and type(data) == "string" and #data > 0 then
            pcall(writefile, T.FILE, data)
        else
            warn("[PulseRevolver][theme] could not download " .. T.URL)
        end
        path, audio = T.findFile()
    end
    if not path then
        local seen = #audio > 0 and table.concat(audio, ", ", 1, math.min(#audio, 8)) or "none"
        warn("[PulseRevolver][theme] " .. T.FILE .. " was not found in your workspace folder. Audio files I can see: " .. seen)
        return nil
    end
    if path ~= T.FILE then print("[PulseRevolver][theme] using " .. path .. " (closest match to " .. T.FILE .. ")") end
    local okRead, data = pcall(readfile, path)
    if not okRead or type(data) ~= "string" or #data == 0 then
        warn("[PulseRevolver][theme] " .. T.FILE .. " could not be read or is empty")
        return nil
    end
    do
        local b1, b2, b3, b4 = string.byte(data, 1, 4)
        local looksMp3 = (string.sub(data, 1, 3) == "ID3") or (b1 == 0xFF and b2 ~= nil and b2 >= 0xE0)
        print(("[PulseRevolver][theme] %s: %d bytes, first bytes %s,%s,%s,%s -> %s"):format(
            path, #data, tostring(b1), tostring(b2), tostring(b3), tostring(b4),
            looksMp3 and "looks like a normal mp3" or "does NOT look like an mp3 (wrong format renamed to .mp3?)"))
    end
    -- copy the song to a cache file and build the asset from the copy (this is what makes it load reliably)
    -- the executor remembers each cache file name, so the name includes the song's size + a checksum:
    -- a different song (or a fixed file) always gets a brand new name and can never play stale data
    local sum = 0
    for i = 1, #data, 4099 do
        sum = (sum + string.byte(data, i) * (i % 251 + 1)) % 1000003
    end
    local baseStem = string.gsub(T.CACHE_FILE, "%.%w+$", "")
    local songTag = string.gsub(string.gsub(T.FILE, "%.%w+$", ""), "[^%w]", "")
    local stem = baseStem .. "_" .. songTag -- every song (mode) gets its own cache files
    local cacheName = stem .. "_" .. #data .. "_" .. sum .. ".mp3"
    -- clean up older cache copies of THIS song (plus the old pre-modes cache names)
    pcall(function()
        if type(delfile) == "function" then
            if isfile(T.CACHE_FILE) then delfile(T.CACHE_FILE) end
            if type(listfiles) == "function" then
                for _, f in ipairs(listfiles(".")) do
                    local name = string.match(f, "[^/\\]+$") or f
                    local olderCopy = string.sub(name, 1, #stem + 1) == stem .. "_" and name ~= cacheName
                    local legacy = string.sub(name, 1, #baseStem + 1) == baseStem .. "_"
                        and tonumber(string.sub(name, #baseStem + 2, #baseStem + 2)) ~= nil
                    if olderCopy or legacy then delfile(f) end
                end
            end
        end
    end)
    local okAsset, asset = pcall(function()
        writefile(cacheName, data)
        return assetFn(cacheName)
    end)
    if not okAsset or not asset or asset == "" then
        warn("[PulseRevolver][theme] getcustomasset failed for " .. T.FILE .. ": " .. tostring(asset))
        return nil
    end
    return asset
end

CONFIG.THEME.stop = function(fade)
    local T = CONFIG.THEME
    T.token = (T.token or 0) + 1
    local sound = T.sound
    T.sound = nil
    if not sound then return end
    if fade and T.FADE_OUT > 0 and sound.Parent then
        sound.Name = "PulseRevolverThemeFading"
        game:GetService("TweenService"):Create(sound, TweenInfo.new(T.FADE_OUT), { Volume = 0 }):Play()
        task.delay(T.FADE_OUT + 0.1, function() sound:Destroy() end)
    else
        sound:Destroy()
    end
end

CONFIG.THEME.setVolume = function(v)
    local T = CONFIG.THEME
    T.VOLUME = math.max(0, tonumber(v) or 0)
    if T.sound and T.sound.Parent then T.sound.Volume = T.VOLUME end
end

CONFIG.THEME.start = function()
    local T = CONFIG.THEME
    local SoundService = game:GetService("SoundService")
    T.stop(false)
    -- remove a leftover theme from an earlier run of this script
    for _, child in ipairs(SoundService:GetChildren()) do
        if child.Name == "PulseRevolverTheme" then child:Destroy() end
    end
    if not T.ENABLED then return end
    local token = T.token
    task.spawn(function()
        local asset = T.getAsset()
        if not asset or token ~= T.token or deleted then return end
        print("[PulseRevolver][theme] asset: " .. tostring(asset))
        -- built in the same order as the working song script: SoundId + Volume first, then parent, then wait for IsLoaded
        local sound = Instance.new("Sound")
        sound.Name = "PulseRevolverTheme"
        sound.SoundId = asset
        sound.Volume = T.VOLUME
        sound.Parent = SoundService
        T.sound = sound
        local waited = 0
        while not sound.IsLoaded and waited < 10 and token == T.token do
            task.wait(0.1)
            waited += 0.1
        end
        if token ~= T.token then sound:Destroy() return end
        if not sound.IsLoaded then
            warn("[PulseRevolver][theme] song is slow to load, trying to play anyway (SoundId=" .. tostring(sound.SoundId) .. ", TimeLength=" .. tostring(sound.TimeLength) .. ")")
        end
        if not sound.IsLoaded then
            local okPre, errPre = pcall(function() game:GetService("ContentProvider"):PreloadAsync({ sound }) end)
            print("[PulseRevolver][theme] PreloadAsync: " .. tostring(okPre) .. " " .. tostring(errPre) .. " | IsLoaded=" .. tostring(sound.IsLoaded) .. " TimeLength=" .. tostring(sound.TimeLength))
        end
        -- loop / speed / start position are only applied once the sound has loaded
        sound.Looped = T.LOOPED
        sound.PlaybackSpeed = T.SPEED
        sound.TimePosition = T.START_TIME
        if T.FADE_IN > 0 then sound.Volume = 0 end
        sound:Play()
        if T.FADE_IN > 0 then
            game:GetService("TweenService"):Create(sound, TweenInfo.new(T.FADE_IN), { Volume = T.VOLUME }):Play()
        end
    end)
end

------------------------------------------------------------------
-- FX: song visualizer ring at your feet, floating particles, idle hand orbs
-- (Everything lives in CONFIG.FX / CONFIG.VISUALIZER / CONFIG.PARTICLES / CONFIG.ORBS.)
------------------------------------------------------------------
CONFIG.FX = { particles = {}, orbAlpha = 0, orbTime = 0, orbFrames = 0, nextParticle = 0, smooth = 0, loudnessColor = false }

-- song loudness (smoothed: fast up, slower down). No cap - STRENGTH decides how hard the bars grow.
CONFIG.FX.updateLoudness = function(dt)
    local FX, V = CONFIG.FX, CONFIG.VISUALIZER
    local sound = CONFIG.THEME.sound
    local loud = (sound and sound.Parent and sound.IsPlaying) and sound.PlaybackLoudness or 0
    local rate = loud > FX.smooth and V.ATTACK or V.RELEASE
    FX.smooth += (loud - FX.smooth) * math.min(1, dt * rate)
end

-- colour of the visualizer ring + particles: the cylinder colour, except for modes with loudnessColor
-- (Immortality Lord): black when quiet -> gray when loud -> pure white when really loud
CONFIG.FX.visualizerColor = function()
    local FX = CONFIG.FX
    if FX.shadeFlicker and CONFIG.GODCAT.currentShade then
        return CONFIG.GODCAT.currentShade() -- God Cat: rapid random shades of black and white
    end
    if FX.loudnessColor then
        local t = math.clamp(FX.smooth / math.max(CONFIG.VISUALIZER.LOUD_WHITE_AT, 1), 0, 1)
        return Color3.new(t, t, t)
    end
    return live.pulse
end

CONFIG.FX.getFolder = function()
    local FX = CONFIG.FX
    if not FX.folder then
        FX.folder = Instance.new("Folder")
        FX.folder.Name = "PulseRevolverFX"
    end
    if FX.folder.Parent ~= workspace then pcall(function() FX.folder.Parent = workspace end) end
    return FX.folder
end

-- the body that is actually visible: the clone while ghosting, otherwise our character
CONFIG.FX.getBody = function()
    if ghostModel and ghostModel.Parent and ghostRoot and ghostRoot.Parent then
        return ghostRoot, ghostModel
    end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then return hrp, char end
    return nil, nil
end

CONFIG.FX.updateFloor = function(dt, bodyRoot)
    local FX = CONFIG.FX
    if not bodyRoot then FX.floorY = nil return end
    local params = FX.rayParams
    if not params then
        params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        FX.rayParams = params
    end
    local ignore = {}
    if player.Character then ignore[#ignore + 1] = player.Character end
    if ghostModel then ignore[#ignore + 1] = ghostModel end
    ignore[#ignore + 1] = ghostFolder
    if model then ignore[#ignore + 1] = model end
    if FX.folder then ignore[#ignore + 1] = FX.folder end
    params.FilterDescendantsInstances = ignore
    local pos = bodyRoot.Position
    local hit = workspace:Raycast(pos, Vector3.new(0, -12, 0), params)
    local y = hit and hit.Position.Y or (pos.Y - 3)
    FX.floorY = FX.floorY and (FX.floorY + (y - FX.floorY) * math.min(1, dt * 25)) or y
end

------------------------------ visualizer ring ------------------------------
CONFIG.FX.buildRing = function()
    local FX, V = CONFIG.FX, CONFIG.VISUALIZER
    if FX.ring then FX.ring.group:Destroy() end
    local group = Instance.new("Folder")
    group.Name = "Visualizer"
    local bars, dirs = {}, {}
    for i = 1, V.BARS do
        local a = (i - 1) / V.BARS * math.pi * 2
        dirs[i] = Vector3.new(math.cos(a), 0, math.sin(a))
        local p = Instance.new("Part")
        p.Name = "Bar"
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Material = Enum.Material.Neon
        p.Color = live.pulse
        p.Transparency = V.TRANSPARENCY
        p.Size = Vector3.new(V.BAR_WIDTH, V.BAR_HEIGHT, V.MIN_LENGTH)
        p.Parent = group
        bars[i] = p
    end
    FX.ring = { group = group, bars = bars, dirs = dirs, cfs = {}, smooth = 0, color = live.pulse }
end

CONFIG.FX.updateRing = function(dt, bodyRoot)
    local FX, V = CONFIG.FX, CONFIG.VISUALIZER
    local ring = FX.ring
    if not V.ENABLED or not bodyRoot or not FX.floorY then
        if ring and ring.group.Parent then ring.group.Parent = nil end
        return
    end
    if not ring then
        FX.buildRing()
        ring = FX.ring
    end
    local folder = FX.getFolder()
    if ring.group.Parent ~= folder then ring.group.Parent = folder end

    local color = FX.visualizerColor()
    if ring.color ~= color then
        ring.color = color
        for _, bar in ipairs(ring.bars) do bar.Color = color end
    end

    local rootPos = bodyRoot.Position
    local center = Vector3.new(rootPos.X, FX.floorY + V.GROUND_OFFSET, rootPos.Z)
    local n = #ring.bars
    -- every bar gets exactly the same length, so the ring is always a perfect circle
    local width = V.BAR_WIDTH
    local len = V.MIN_LENGTH + FX.smooth * (FX.strength or V.STRENGTH)
    local dist = V.RADIUS + len * 0.5
    local resize = ring.lastLen ~= len or ring.lastWidth ~= width
    ring.lastLen, ring.lastWidth = len, width
    for i = 1, n do
        local dir = ring.dirs[i]
        local pos = center + dir * dist
        if resize then ring.bars[i].Size = Vector3.new(width, V.BAR_HEIGHT, len) end
        ring.cfs[i] = CFrame.lookAt(pos, pos + dir)
    end
    workspace:BulkMoveTo(ring.bars, ring.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

------------------------------ floating particles ------------------------------
CONFIG.FX.spawnParticle = function(rootPos)
    local FX, P = CONFIG.FX, CONFIG.PARTICLES
    if #FX.particles >= P.MAX_ACTIVE then return end
    local angle = math.random() * math.pi * 2
    local minR, maxR = P.MIN_RADIUS, P.MAX_RADIUS
    local radius = math.sqrt(minR * minR + math.random() * (maxR * maxR - minR * minR)) -- even spread over the area
    local floorY = (FX.floorY or (rootPos.Y - 3)) + 0.1
    local start = Vector3.new(rootPos.X + math.cos(angle) * radius, floorY + math.random() * 1.5, rootPos.Z + math.sin(angle) * radius)

    -- "right" = the camera's right (flattened), so the drift looks left/right on screen
    local cam = workspace.CurrentCamera
    local right = Vector3.xAxis
    if cam then
        local rv = cam.CFrame.RightVector
        local flat = Vector3.new(rv.X, 0, rv.Z)
        if flat.Magnitude > 0.01 then right = flat.Unit end
    end
    local tilt = math.rad((math.random() * 2 - 1) * P.MAX_TILT) -- negative = left, positive = right, ~0 = straight up
    local dir = Vector3.yAxis * math.cos(tilt) + right * math.sin(tilt)
    local perp = right * math.cos(tilt) - Vector3.yAxis * math.sin(tilt)

    local p = Instance.new("Part")
    p.Name = "Mote"
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Material = Enum.Material.Neon
    p.Color = FX.visualizerColor()
    p.Transparency = 1
    p.Size = Vector3.new(P.WIDTH, P.LENGTH, P.WIDTH)
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Sphere
    mesh.Parent = p
    p.CFrame = CFrame.fromMatrix(start, perp, dir)
    p.Parent = CONFIG.FX.getFolder()
    FX.particles[#FX.particles + 1] = {
        part = p, start = start, dir = dir, perp = perp, born = os.clock(),
        life = P.LIFETIME_MIN + math.random() * (P.LIFETIME_MAX - P.LIFETIME_MIN),
        speed = P.RISE_MIN + math.random() * (P.RISE_MAX - P.RISE_MIN),
    }
end

CONFIG.FX.updateParticles = function(dt, bodyRoot)
    local FX, P = CONFIG.FX, CONFIG.PARTICLES
    local now = os.clock()
    if P.ENABLED and bodyRoot and now >= FX.nextParticle then
        FX.spawnParticle(bodyRoot.Position)
        FX.nextParticle = now + P.SPAWN_MIN + math.random() * (P.SPAWN_MAX - P.SPAWN_MIN)
    end
    local list = FX.particles
    local color = FX.visualizerColor()
    for i = #list, 1, -1 do
        local e = list[i]
        local age = now - e.born
        if age >= e.life or not e.part.Parent then
            e.part:Destroy()
            table.remove(list, i)
        else
            local k = age / e.life
            local a = 1
            if k < 0.2 then a = k / 0.2 elseif k > 0.6 then a = 1 - (k - 0.6) / 0.4 end
            e.part.Transparency = 1 - a * 0.75
            e.part.CFrame = CFrame.fromMatrix(e.start + e.dir * (e.speed * age), e.perp, e.dir)
            if e.part.Color ~= color then e.part.Color = color end
        end
    end
end

------------------------------ idle hand orbs ------------------------------
CONFIG.FX.buildOrbs = function()
    local FX, O = CONFIG.FX, CONFIG.ORBS
    FX.orbs = {}
    local function ball(size, name)
        local p = Instance.new("Part")
        p.Name = name
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(size, size, size)
        p.Material = Enum.Material.Neon
        p.Color = live.pulse
        p.Transparency = 1
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        return p
    end
    for i = 1, 2 do
        local core = ball(O.SIZE, "OrbCore")
        local glow = ball(O.SIZE * 2.4, "OrbGlow")
        local light = Instance.new("PointLight")
        light.Range = 5
        light.Brightness = 0
        light.Shadows = false
        light.Color = live.pulse
        light.Parent = core
        local a0 = Instance.new("Attachment")
        a0.Position = Vector3.new(0, O.TRAIL_WIDTH * 0.5, 0)
        a0.Parent = core
        local a1 = Instance.new("Attachment")
        a1.Position = Vector3.new(0, -O.TRAIL_WIDTH * 0.5, 0)
        a1.Parent = core
        local trail = Instance.new("Trail")
        trail.Attachment0, trail.Attachment1 = a0, a1
        trail.Lifetime = O.TRAIL_LIFETIME
        trail.MinLength = 0.02
        trail.FaceCamera = true
        trail.LightEmission = 1
        trail.LightInfluence = 0
        trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
        trail.Transparency = NumberSequence.new(1)
        trail.Enabled = false
        trail.Parent = core
        FX.orbs[i] = {
            core = core, glow = glow, light = light, trail = trail,
            dir = (i == 1) and 1 or -1,                      -- opposite spin directions
            radius = O.RADIUS * ((i == 1) and 1 or 1.3),
            phase = (i == 1) and 0 or math.pi,
            lastAlpha = -1, color = nil,
        }
    end
end

CONFIG.FX.hideOrbs = function()
    local FX = CONFIG.FX
    if not FX.orbsShown then return end
    FX.orbsShown, FX.orbFrames = false, 0
    for _, orb in ipairs(FX.orbs) do
        orb.trail.Enabled = false
        orb.core.Parent = nil
        orb.glow.Parent = nil
        orb.lastAlpha = -1
    end
end

CONFIG.FX.updateOrbs = function(dt, bodyModel)
    local FX, O = CONFIG.FX, CONFIG.ORBS
    -- the orbs exist for as long as Idle 1 (the main idle) is playing; Idle 2 plays no part in this.
    -- They fade out when we walk (Idle 1 is stopped) or while a move animation is running.
    local idle = animReady and trk.idle or nil
    local wanted = idle ~= nil and want[idle] == true
    local active = O.ENABLED and bodyModel ~= nil and wanted and not ov
    local arm = bodyModel and bodyModel:FindFirstChild("Left Arm")
    if not arm or not arm:IsA("BasePart") then active = false end

    if O.DEBUG then
        local now = os.clock()
        if now - (FX.debugAt or 0) >= 2 then
            FX.debugAt = now
            print(("[PulseRevolver][orbs] wanted=%s ov=%s arm=%s active=%s alpha=%.2f idleLen=%.2f idleTime=%.2f"):format(
                tostring(wanted), tostring(ov), tostring(arm ~= nil), tostring(active), FX.orbAlpha,
                idle and idle.Length or 0, idle and idle.TimePosition or 0))
        end
    end

    local step = active and dt / math.max(O.FADE_IN, 0.01) or -dt / math.max(O.FADE_OUT, 0.01)
    FX.orbAlpha = math.clamp(FX.orbAlpha + step, 0, 1)
    if FX.orbAlpha <= 0 then
        if FX.orbs then FX.hideOrbs() end
        FX.orbTime = 0
        return
    end
    if not FX.orbs then FX.buildOrbs() end
    local folder = FX.getFolder()
    if not FX.orbsShown then
        FX.orbsShown, FX.orbFrames = true, 0
        for _, orb in ipairs(FX.orbs) do
            orb.core.Parent = folder
            orb.glow.Parent = folder
        end
    end
    if not arm then return end

    -- grab the left arm and the front (hand end) of it; the orbs circle around the hand, along the arm's direction
    local axis = -arm.CFrame.UpVector
    local tip = arm.Position + axis * (arm.Size.Y * 0.5)
    local center = tip + axis * O.FORWARD_OFFSET
    local ref = (math.abs(axis.Y) > 0.95) and Vector3.xAxis or Vector3.yAxis
    local u = axis:Cross(ref).Unit
    local v = axis:Cross(u)
    FX.orbTime += dt
    FX.orbFrames += 1
    local alpha = FX.orbAlpha
    local color = live.pulse
    for i, orb in ipairs(FX.orbs) do
        local ang = orb.phase + orb.dir * FX.orbTime * math.rad(O.SPEED)
        local pos = center + (u * math.cos(ang) + v * math.sin(ang)) * orb.radius
            + axis * (math.sin(FX.orbTime * 2.3 + i * 2) * 0.1)
        local cf = CFrame.new(pos)
        orb.core.CFrame = cf
        orb.glow.CFrame = cf
        if orb.color ~= color then
            orb.color = color
            orb.core.Color, orb.glow.Color, orb.light.Color = color, color, color
            orb.trail.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color)
        end
        if orb.lastAlpha ~= alpha then
            orb.lastAlpha = alpha
            orb.core.Transparency = 1 - alpha
            orb.glow.Transparency = 1 - alpha * 0.3
            orb.light.Brightness = 1.2 * alpha
            orb.trail.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1 - alpha * 0.85), NumberSequenceKeypoint.new(1, 1),
            })
        end
        -- the trail only starts after the orb has been positioned, so it never streaks in from the old spot
        orb.trail.Enabled = FX.orbFrames >= 2 and alpha > 0.05
    end
end

CONFIG.FX.safe = function(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local FX = CONFIG.FX
        FX.warnedParts = FX.warnedParts or {}
        if not FX.warnedParts[name] then
            FX.warnedParts[name] = true
            warn("[PulseRevolver][fx:" .. name .. "] " .. tostring(err))
        end
    end
end

CONFIG.FX.update = function(dt)
    local FX = CONFIG.FX
    local bodyRoot, bodyModel = FX.getBody()
    FX.safe("floor", FX.updateFloor, dt, bodyRoot)
    FX.safe("loudness", FX.updateLoudness, dt)
    FX.safe("ring", FX.updateRing, dt, bodyRoot)
    FX.safe("particles", FX.updateParticles, dt, bodyRoot)
    FX.safe("orbs", FX.updateOrbs, dt, bodyModel)
end

CONFIG.FX.step = function(dt)
    if deleted then return end
    local ok, err = pcall(CONFIG.FX.update, dt)
    if not ok and not CONFIG.FX.warned then
        CONFIG.FX.warned = true
        warn("[PulseRevolver][fx] " .. tostring(err))
    end
end

CONFIG.FX.destroy = function()
    local FX = CONFIG.FX
    if FX.folder then FX.folder:Destroy() FX.folder = nil end
    FX.ring, FX.orbs, FX.orbsShown = nil, nil, false
    FX.particles = {}
end

------------------------------------------------------------------
-- DELETE (C): same animation + fire sound as move 1, but the tracer cannot affect targets.
-- Every part the tracer passes through (it raycasts THROUGH parts) turns the tip colour, shakes,
-- fades out, loses collision, and regrows with collision RESPAWN_TIME seconds later.
-- Workspace.Live, Workspace.Players and every player character are never touched.
------------------------------------------------------------------
CONFIG.DELETE.start = function()
    local D = CONFIG.DELETE
    if deleted or not animReady or CONFIG.FLOW.active then return end
    if ov ~= nil and ov ~= "taunt" then return end
    if os.clock() < D.readyAt then return end
    if ov == "taunt" then stopTrack(trk.taunt, 0.1) end
    D.readyAt = os.clock() + D.COOLDOWN
    D.pending = true -- animStep fires Delete (instead of move 1) when the shoot animation reaches its fire frame
    ov = "shoot1"
    playTrack(trk.shoot1, 0.05, 0, 1)
end

CONFIG.DELETE.buildIgnore = function()
    local D = CONFIG.DELETE
    local list = {}
    local function add(inst) if inst then list[#list + 1] = inst end end
    for _, name in ipairs(D.IGNORE_FOLDERS) do add(workspace:FindFirstChild(name)) end
    for _, plr in ipairs(Players:GetPlayers()) do add(plr.Character) end
    add(ghostFolder)
    add(ghostModel)
    add(model)
    add(CONFIG.FX.folder)
    add(workspace.CurrentCamera)
    add(workspace.Terrain)
    for part in pairs(D.registry) do add(part) end -- parts that are already deleted
    return list
end

-- where the cursor points (characters under the cursor are fine here, this is only the aim)
CONFIG.DELETE.getAimPoint = function()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if player.Character then ignore[#ignore + 1] = player.Character end
    if model then ignore[#ignore + 1] = model end
    if ghostModel then ignore[#ignore + 1] = ghostModel end
    ignore[#ignore + 1] = ghostFolder
    if CONFIG.FX.folder then ignore[#ignore + 1] = CONFIG.FX.folder end
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
    return hit and hit.Position or (ray.Origin + ray.Direction * 2000)
end

-- collects EVERY part along the ray: each hit part is excluded and the ray is cast again,
-- so the tracer goes straight through parts instead of stopping at the first one
CONFIG.DELETE.collect = function(origin, direction, range)
    local D = CONFIG.DELETE
    local ignore = D.buildIgnore()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local hits = {}
    for _ = 1, D.MAX_PARTS + 25 do
        params.FilterDescendantsInstances = ignore
        local result = workspace:Raycast(origin, direction * range, params)
        if not result then break end
        local inst = result.Instance
        ignore[#ignore + 1] = inst
        if inst:IsA("BasePart") and not inst:IsA("Terrain") then
            hits[#hits + 1] = inst
            if #hits >= D.MAX_PARTS then break end
        end
    end
    return hits
end

CONFIG.DELETE.apply = function(part)
    local D = CONFIG.DELETE
    if D.registry[part] or not part.Parent then return end
    D.registry[part] = {
        cf = part.CFrame, color = part.Color, transparency = part.Transparency,
        canCollide = part.CanCollide, canQuery = part.CanQuery, anchored = part.Anchored,
        phase = "fade", hitAt = os.clock(), regrowAt = 0,
    }
    D.count += 1
    pcall(function()
        part.Color = live.muzzle      -- same colour as the tip glow
        part.CanCollide = false       -- no collision from the moment it is shot
        part.CanQuery = false         -- later raycasts / aim also pass through it while it is gone
        part.Anchored = true          -- so loose parts do not fall away while they are gone
    end)
    if not D.conn then D.conn = RunService.Heartbeat:Connect(D.step) end
end

CONFIG.DELETE.restorePart = function(part, e, resetPosition)
    pcall(function()
        if resetPosition then part.CFrame = e.cf end
        part.Color = e.color
        part.Transparency = e.transparency
        part.CanCollide = e.canCollide
        part.CanQuery = e.canQuery
        part.Anchored = e.anchored
    end)
end

CONFIG.DELETE.step = function()
    local D = CONFIG.DELETE
    local now = os.clock()
    for part, e in pairs(D.registry) do
        if not part.Parent then
            D.registry[part] = nil
            D.count -= 1
        elseif e.phase == "fade" then
            local a = math.clamp((now - e.hitAt) / math.max(D.FADE_OUT, 0.01), 0, 1)
            part.Transparency = e.transparency + (1 - e.transparency) * a
            if a < 1 then
                local s = D.SHAKE
                part.CFrame = e.cf * CFrame.new((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)
            else
                part.CFrame = e.cf
                e.phase = "gone"
            end
        elseif e.phase == "gone" then
            if now >= e.hitAt + D.RESPAWN_TIME then
                e.phase, e.regrowAt = "regrow", now
                part.Color = e.color -- still invisible, so the colour can go back unseen
            end
        else
            local a = math.clamp((now - e.regrowAt) / math.max(D.FADE_IN, 0.01), 0, 1)
            part.Transparency = 1 + (e.transparency - 1) * a
            if a >= 1 then
                D.restorePart(part, e, false) -- collision (and everything else) comes back once it is fully visible
                D.registry[part] = nil
                D.count -= 1
            end
        end
    end
    if D.count <= 0 and D.conn then
        D.conn:Disconnect()
        D.conn = nil
        D.count = 0
    end
end

-- puts every deleted part back immediately (used when the script is deleted)
CONFIG.DELETE.restoreAll = function()
    local D = CONFIG.DELETE
    if D.conn then D.conn:Disconnect() D.conn = nil end
    for part, e in pairs(D.registry) do
        D.restorePart(part, e, true)
        D.registry[part] = nil
    end
    D.count = 0
end

CONFIG.DELETE.beam = function(origin, endpoint)
    local length = (endpoint - origin).Magnitude
    if length < 0.5 then return end
    if length > 2000 then -- a Part cannot be longer than 2048 studs
        endpoint = origin + (endpoint - origin).Unit * 2000
        length = 2000
    end
    if CONFIG.LC.isActive() then
        CONFIG.LC.beam(origin, endpoint) -- Lightning Cannon: lightning beam instead of the normal tracer
        return
    end
    local beam = Instance.new("Part")
    beam.Name = "PulseDeleteBeam"
    beam.Shape = Enum.PartType.Cylinder
    beam.Material = M.Neon
    beam.Color = live.muzzle
    beam.Transparency = 1
    beam.Anchored = true
    beam.CanCollide = false
    beam.CanTouch = false
    beam.CanQuery = false
    beam.CastShadow = false
    beam.Size = Vector3.new(length, CONFIG.BULLET_THICKNESS, CONFIG.BULLET_THICKNESS)
    beam.CFrame = CFrame.lookAt((origin + endpoint) / 2, endpoint) * CFrame.Angles(0, math.pi / 2, 0)
    beam.Parent = workspace
    local fadeIn, hold, fadeOut = CONFIG.BULLET_FADE_IN, CONFIG.BULLET_HOLD, CONFIG.BULLET_FADE_OUT
    local start = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        local t = os.clock() - start
        if t >= fadeIn + hold + fadeOut then conn:Disconnect() beam:Destroy() return end
        if t < fadeIn then beam.Transparency = 1 - t / fadeIn
        elseif t < fadeIn + hold then beam.Transparency = 0
        else beam.Transparency = (t - fadeIn - hold) / fadeOut end
        beam.Color = live.muzzle
    end)
end

CONFIG.DELETE.fire = function()
    local D = CONFIG.DELETE
    local zone = muzzleZone
    local origin = zone and zone.Position or (animHrp and animHrp.Position)
    if not origin then return end
    CONFIG.LC.playFire(CONFIG.SOUND_FIRE, zone or animHrp) -- same fire sound as move 1

    local aim = D.getAimPoint()
    if not aim then return end
    local offset = aim - origin
    local distance = offset.Magnitude
    if distance < 0.5 then
        local cam = workspace.CurrentCamera
        if not cam then return end
        offset, distance = cam.CFrame.LookVector, 1
    end
    local direction = offset.Unit
    local range = D.PIERCE_THROUGH and D.RANGE or distance
    local endpoint = origin + direction * range

    D.beam(origin, endpoint) -- tracer only: no hit effect, no orbit, nothing is targeted
    for _, part in ipairs(D.collect(origin, direction, range)) do
        D.apply(part)
    end
end


------------------------------------------------------------------
-- IDLE PATTERNS + ANIMATION REPLACEMENTS (both are set per mode in CONFIG.MODES.list)
--   idle / idle2 = { id, kind, ... }
--     kind "hold"        : play once, then freeze on the last frame (the original Idle 1)
--     kind "once"        : play once from the start (the original Idle 2)
--     kind "loop"        : loop the whole animation
--     kind "segmentLoop" : loop only from..to
--     kind "segmentOnce" : play only from..to one time
--     kind "pingpong"    : play from..to, wait waitEnd, play it backwards to from, wait waitStart, repeat (once = true: only one loop, then it ends)
--   replace = { [detected animation id] = replacement animation id }
------------------------------------------------------------------
CONFIG.IDLE.digits = function(id) return string.match(tostring(id), "(%d+)") end
CONFIG.IDLE.normalize = function(id) return "rbxassetid://" .. CONFIG.IDLE.digits(id) end

-- the time (seconds) a segment stops at, kept inside the real animation length
CONFIG.IDLE.endOf = function(track, spec)
    local to = spec.to or track.Length
    if track.Length > 0 then to = math.min(to, track.Length - 0.02) end
    return to
end

CONFIG.IDLE.setSpecs = function(mode)
    local I = CONFIG.IDLE
    I.spec1 = mode.idle or { id = ANIM.IDLE, kind = "hold" }
    if mode.idle2 then
        I.spec2 = mode.idle2
    elseif mode.idle then
        I.spec2 = nil -- a custom idle without an idle 2 means: no idle 2 in this mode
    else
        I.spec2 = { id = ANIM.IDLE2, kind = "once" }
    end
    I.layerSpec = mode.idleLayer -- optional 2nd idle that plays at the same time (God Cat)
    I.state1, I.state2 = {}, {}
    idleHeld = false
    -- the ghost sync mutes these ids while the clone walks
    Perf.idleId = I.digits(I.spec1.id)
    Perf.idle2Id = I.spec2 and I.digits(I.spec2.id) or "none"
end

-- start idle 1 (slot 1) or idle 2 (slot 2) with its pattern
CONFIG.IDLE.begin = function(slot)
    local I = CONFIG.IDLE
    local track = (slot == 1) and trk.idle or trk.idle2
    local spec = (slot == 1) and I.spec1 or I.spec2
    if not track or not spec then return end
    local state = { phase = "fwd", timer = 0, pos = 0 }
    if slot == 1 then I.state1, idleHeld = state, false else I.state2 = state end
    local kind = spec.kind
    local start = (kind == "segmentLoop" or kind == "segmentOnce" or kind == "pingpong") and (spec.from or 0) or 0
    playTrack(track, (slot == 1) and 0.2 or 0.25, start, 1)
end

-- forward from..to, wait, backwards to..from, wait, forward again ...
CONFIG.IDLE.pingpong = function(track, spec, state, dt)
    local from, to = spec.from or 0, CONFIG.IDLE.endOf(track, spec)
    if state.phase == "fwd" then
        if track.TimePosition >= to then
            state.phase, state.timer = "holdEnd", spec.waitEnd or 0
            wantSpeed[track] = 0
            track:AdjustSpeed(0)
            track.TimePosition = to
            lastTime[track] = to
        end
    elseif state.phase == "holdEnd" then
        state.timer -= dt
        if state.timer <= 0 then state.phase, state.pos = "rev", to end
    elseif state.phase == "rev" then
        state.pos -= dt -- real time, so it plays backwards at normal speed
        if state.pos <= from then
            state.pos = from
            state.phase, state.timer = "holdStart", spec.waitStart or 0
        end
        track.TimePosition = state.pos
        lastTime[track] = state.pos
    elseif state.phase == "holdStart" then
        track.TimePosition = from
        lastTime[track] = from
        state.timer -= dt
        if state.timer <= 0 then
            if spec.once then
                state.finished = true -- one single loop only: the idle ends here
            else
                state.phase = "fwd"
                wantSpeed[track] = 1
                track:AdjustSpeed(1)
            end
        end
    end
end

CONFIG.IDLE.step = function(dt, moving)
    local I = CONFIG.IDLE
    local idle, idle2 = trk.idle, trk.idle2
    local s1, s2 = I.spec1, I.spec2
    if idle and s1 and want[idle] then
        local kind = s1.kind
        if kind == "hold" then
            if not idleHeld and idle.Length > 0 and idle.TimePosition >= idle.Length - 0.05 then
                idleHeld = true
                wantSpeed[idle] = 0
                idle:AdjustSpeed(0)
                idle.TimePosition = idle.Length - 0.05
                lastTime[idle] = idle.TimePosition
            end
        elseif kind == "segmentLoop" then
            if idle.TimePosition >= I.endOf(idle, s1) then
                idle.TimePosition = s1.from or 0
                lastTime[idle] = s1.from or 0
            end
        elseif kind == "pingpong" then
            I.pingpong(idle, s1, I.state1, dt)
        end -- "loop" needs nothing: the track itself loops
    end
    if idle2 and s2 then
        if want[idle2] then
            local finished = false
            local kind = s2.kind
            if kind == "once" then
                finished = idle2.TimePosition >= idle2.Length - 0.05
            elseif kind == "segmentOnce" then
                finished = idle2.TimePosition >= I.endOf(idle2, s2)
            elseif kind == "segmentLoop" then
                if idle2.TimePosition >= I.endOf(idle2, s2) then
                    idle2.TimePosition = s2.from or 0
                    lastTime[idle2] = s2.from or 0
                end
            elseif kind == "pingpong" then
                I.pingpong(idle2, s2, I.state2, dt)
                finished = I.state2.finished == true
            end
            if moving or ov or finished then
                stopTrack(idle2, 0.25)
                idle2ReadyAt = os.clock() + CONFIG.IDLE2_COOLDOWN
            end
        elseif not moving and not ov and stillTime >= CONFIG.IDLE2_AFTER and os.clock() >= idle2ReadyAt then
            I.begin(2)
        end
    end
end

-- optional 2nd idle that plays AT THE SAME TIME as the main idle (mode.idleLayer = { id, from, to })
--   to <= from : frozen pose held on `from`      to > from : loops only from..to
CONFIG.IDLE.layerStep = function(dt)
    local I = CONFIG.IDLE
    local spec, track = I.layerSpec, trk.layer
    if not track then return end
    if not spec then
        if want[track] then stopTrack(track, 0.15) end
        return
    end
    local from, to = spec.from or 0, spec.to or spec.from or 0
    if track.Length > 0 then
        from = math.min(from, track.Length - 0.02)
        to = math.min(to, track.Length - 0.02)
    end
    local hold = to <= from
    if not want[track] then
        playTrack(track, 0.2, from, hold and 0 or 1)
    end
    if hold then
        if wantSpeed[track] ~= 0 then wantSpeed[track] = 0 track:AdjustSpeed(0) end
        if track.IsPlaying and math.abs(track.TimePosition - from) > 0.005 then track.TimePosition = from end
        lastTime[track] = from
    elseif track.TimePosition >= to then
        track.TimePosition = from
        lastTime[track] = from
    end
end

-- swap the loaded idle tracks to the ones of the current mode (the tracks used after a respawn come from setupAnimations)
CONFIG.IDLE.rebuild = function()
    local I = CONFIG.IDLE
    if not animReady or not animator then return end
    I.rebuildToken = (I.rebuildToken or 0) + 1
    local token, myAnim = I.rebuildToken, animToken
    local an = animator
    local spec1, spec2, layerSpec = I.spec1, I.spec2, I.layerSpec
    task.spawn(function()
        local P = Enum.AnimationPriority
        local newIdle = loadTrack(an, I.normalize(spec1.id), spec1.priority or P.Action, spec1.kind == "loop")
        local newIdle2 = spec2 and loadTrack(an, I.normalize(spec2.id), spec2.priority or P.Action2, spec2.kind == "loop") or nil
        local newLayer = layerSpec and loadTrack(an, I.normalize(layerSpec.id), layerSpec.priority or P.Action3, false) or nil
        if deleted or token ~= I.rebuildToken or myAnim ~= animToken then return end
        for _, old in ipairs({ trk.idle, trk.idle2 }) do
            want[old] = nil
            pcall(function() old:Stop(0.15) end)
        end
        if trk.layer then
            want[trk.layer] = nil
            pcall(function() trk.layer:Stop(0.15) end)
        end
        trk.idle, trk.idle2, trk.layer = newIdle, newIdle2, newLayer
        idleHeld, idle2ReadyAt = false, 0
        I.state1, I.state2 = {}, {}
    end)
end

------------------------------ animation replacement ------------------------------
CONFIG.REPLACE.stopAll = function()
    for _, track in pairs(CONFIG.REPLACE.tracks) do
        pcall(function() track:Stop(0.1) end)
    end
end

CONFIG.REPLACE.reset = function() -- the animator changed (respawn / unload): the loaded tracks are gone
    local R = CONFIG.REPLACE
    R.stopAll()
    R.tracks, R.loading, R.lastTrigger, R.started = {}, {}, {}, {}
end

CONFIG.REPLACE.getTrack = function(id)
    local R = CONFIG.REPLACE
    if R.tracks[id] then return R.tracks[id] end
    if not animReady or not animator then return nil end
    if R.loading[id] then
        local waited = 0
        while R.loading[id] and waited < 3.5 do waited += task.wait() end
        return R.tracks[id]
    end
    R.loading[id] = true
    local myAnim = animToken
    local ok, track = pcall(loadTrack, animator, "rbxassetid://" .. id, Enum.AnimationPriority.Action4, false)
    R.loading[id] = nil
    if ok and track and myAnim == animToken then
        R.tracks[id] = track
        return track
    end
    return nil
end

CONFIG.REPLACE.preload = function()
    local R = CONFIG.REPLACE
    local ids = {}
    for _, target in pairs(R.map) do ids[#ids + 1] = target end
    task.spawn(function()
        for _, id in ipairs(ids) do
            if deleted or not animReady then return end
            R.getTrack(id)
        end
    end)
end

CONFIG.REPLACE.setMap = function(map)
    local R = CONFIG.REPLACE
    R.stopAll()
    R.map = {}
    for detect, replacement in pairs(map or {}) do
        R.map[CONFIG.IDLE.digits(detect)] = CONFIG.IDLE.digits(replacement)
    end
    R.preload()
end

-- called the moment another animation starts on our character: if the current mode replaces it,
-- the original is cancelled right away and the replacement plays instead
CONFIG.REPLACE.handle = function(detected)
    local R = CONFIG.REPLACE
    local id = animationIdOf(detected)
    local target = id and R.map[id]
    if not target then return end
    local now = os.clock()
    if now - (R.lastTrigger[id] or 0) < 0.08 then return end -- the event and the per-frame check can both see the same play
    R.lastTrigger[id] = now
    pcall(function() detected:Stop(0) end)
    local track = R.getTrack(target)
    if not track or deleted then return end
    -- Lightning Cannon: when the 2nd replacement animation starts, the 1st one is force-ended (even if it is stuck)
    if CONFIG.LC.isActive() and target ~= CONFIG.LC.FIRE_ANIM_ID then
        local first = R.tracks[CONFIG.LC.FIRE_ANIM_ID]
        if first then
            pcall(function() first:Stop(0) end)
            R.started[first] = nil
        end
    end
    for _, other in pairs(R.tracks) do
        if other ~= track and other.IsPlaying then other:Stop(0.05) end
    end
    track:Stop(0)
    track:Play(0.05)
    track.TimePosition = 0
    track:AdjustSpeed(1)
    R.started[track] = { t = os.clock() } -- watched by CONFIG.REPLACE.watchdog
    CONFIG.LC.onReplacementPlayed(target, track) -- Lightning Cannon: shot + V move after FIRE_DELAY of the first animation
end


-- Lightning Cannon safety net: a replacement animation is never allowed to keep playing after it should have ended.
-- Once it reaches its end (or has been running longer than its length + END_GRACE) it is stopped,
-- so it can never get stuck in the middle and block the idle / other animations.
CONFIG.REPLACE.END_GRACE = 0.25 -- extra seconds allowed past the animation's length before it is cut
CONFIG.REPLACE.watchdog = function()
    local R = CONFIG.REPLACE
    if deleted then return end
    if not CONFIG.LC.isActive() then
        if next(R.started) then R.started = {} end
        return
    end
    local now = os.clock()
    for track, info in pairs(R.started) do
        if not track.IsPlaying then
            R.started[track] = nil
        else
            local length = track.Length
            local speed = math.max(math.abs(track.Speed), 0.05)
            local limit = (length > 0 and length or 8) / speed + R.END_GRACE
            local finished = length > 0 and track.TimePosition >= length - 0.02
            local age = now - info.t
            if age > limit + 0.5 then
                -- still playing well past the end: hard stop
                pcall(function() track:Stop(0) end)
                R.started[track] = nil
            elseif finished or age > limit then
                if not info.stopping then
                    info.stopping = true
                    pcall(function() track:Stop(0.1) end)
                end
            end
        end
    end
end
CONFIG.REPLACE.conn = RunService.Heartbeat:Connect(CONFIG.REPLACE.watchdog)

-- safe defaults (the first mode overwrites these on startup)
CONFIG.IDLE.setSpecs({})

-- P / L: cycle the Attack Mode (E) and the Bring Mode (R) and update their lines in the moves box
CONFIG.ATTACK.refresh = function()
    if MovesBox.attackLine then MovesBox.attackLine.Text = "P - Kill Mode : " .. CONFIG.ATTACK.mode() end
end
CONFIG.ATTACK.cycle = function()
    local A = CONFIG.ATTACK
    if deleted then return end
    A.index = A.index % #A.modes + 1
    A.refresh()
end
CONFIG.BRING.refresh = function()
    if MovesBox.bringLine then MovesBox.bringLine.Text = "L - Bring Mode : " .. CONFIG.BRING.modes[CONFIG.BRING.index] end
end
CONFIG.BRING.cycle = function()
    local B = CONFIG.BRING
    if deleted then return end
    B.index = B.index % #B.modes + 1
    B.refresh()
end

------------------------------------------------------------------
-- GOD CAT: horns on the body AND on the clone, rapid black/white shade flicker
--   * while the God Cat mode is selected, horns are kept on the real character's Head
--     and, whenever the clone (ghost) exists, on the clone's Head too
--   * switching to another mode (or deleting the script) removes them again
------------------------------------------------------------------
do
    local G = CONFIG.GODCAT
    local HORNS_NAME = "GodCatHorns"
    G.active, G.shade, G.nextShadeAt, G.nextFlickerAt, G.nextEnsureAt = false, Color3.new(1, 1, 1), 0, 0, 0

    -- a random shade from the SHADES list: black, dark gray, gray, light gray, dark white, white ...
    G.randomShade = function()
        local list = G.SHADES
        local v = list[math.random(1, #list)]
        return Color3.new(v, v, v)
    end

    -- one shared shade that changes every FLICKER_RATE seconds (used by the visualizer ring + particles)
    G.currentShade = function()
        local now = os.clock()
        if now >= G.nextShadeAt then
            G.nextShadeAt = now + G.FLICKER_RATE
            G.shade = G.randomShade()
        end
        return G.shade
    end

    -- builds the two horns on `head` and parents the model to `body` (the character or the clone)
    G.buildHorns = function(body, head)
        local horns = Instance.new("Model")
        horns.Name = HORNS_NAME
        for _, side in ipairs({ 1, -1 }) do -- 1 = right, -1 = left
            local pos = Vector3.new(side * G.HORN_SIDE_OFFSET, head.Size.Y / 2 - 0.05, G.HORN_FRONT_OFFSET)
            for i = 1, G.HORN_SEGMENTS do
                local t = (i - 1) / (G.HORN_SEGMENTS - 1)
                local phi = math.rad(G.HORN_START_ANGLE + (G.HORN_END_ANGLE - G.HORN_START_ANGLE) * t)
                local out = math.rad(G.HORN_OUTWARD)
                -- phi > 0 leans toward the front (-Z), phi < 0 leans backward (+Z)
                local dir = Vector3.new(side * math.sin(out), math.cos(phi), -math.sin(phi)).Unit
                local radius = G.HORN_BASE_RADIUS + (G.HORN_TIP_RADIUS - G.HORN_BASE_RADIUS) * t
                local center = pos + dir * (G.HORN_SEG_LENGTH / 2)
                local y = dir:Cross(Vector3.new(1, 0, 0)).Unit
                local z = dir:Cross(y)

                local part = Instance.new("Part")
                part.Name = "HornSegment"
                part.Shape = Enum.PartType.Cylinder
                part.Size = Vector3.new(G.HORN_SEG_LENGTH * 1.35, radius * 2, radius * 2)
                part.Material = Enum.Material.Neon
                part.Color = G.randomShade()
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
                part.CastShadow = false
                part.Massless = true
                part.Anchored = false
                part.TopSurface = Enum.SurfaceType.Smooth
                part.BottomSurface = Enum.SurfaceType.Smooth
                part.CFrame = head.CFrame * CFrame.fromMatrix(center, dir, y, z)
                part.Parent = horns

                local weld = Instance.new("WeldConstraint")
                weld.Part0 = head
                weld.Part1 = part
                weld.Parent = part

                pos = pos + dir * (G.HORN_SEG_LENGTH * 0.9)
            end
        end
        horns.Parent = body
        return horns
    end

    local function hornsValid(body, head)
        local horns = body:FindFirstChild(HORNS_NAME)
        if not horns then return false end
        local seg = horns:FindFirstChildWhichIsA("BasePart")
        local weld = seg and seg:FindFirstChildOfClass("WeldConstraint")
        return weld ~= nil and weld.Part0 == head
    end

    local function removeFrom(body)
        if not body then return end
        local old = body:FindFirstChild(HORNS_NAME)
        while old do
            old:Destroy()
            old = body:FindFirstChild(HORNS_NAME)
        end
    end

    -- makes sure `body` (character or clone) has working horns on ITS OWN head
    local function ensureOn(body)
        if not body or not body.Parent then return end
        local head = body:FindFirstChild("Head")
        if not head or not head:IsA("BasePart") then return end
        if hornsValid(body, head) then return end
        removeFrom(body) -- a broken / half-copied set: rebuild it on this head
        G.buildHorns(body, head)
    end

    local function flicker(body)
        local horns = body and body:FindFirstChild(HORNS_NAME)
        if not horns then return end
        for _, seg in ipairs(horns:GetChildren()) do
            if seg:IsA("BasePart") then seg.Color = G.randomShade() end
        end
    end

    G.update = function()
        if deleted or not G.active then return end
        local now = os.clock()
        if now >= G.nextEnsureAt then
            G.nextEnsureAt = now + 0.3
            ensureOn(player.Character)
            if ghostModel and ghostModel.Parent then ensureOn(ghostModel) end -- the clone gets its own horns
        end
        if now >= G.nextFlickerAt then
            G.nextFlickerAt = now + G.FLICKER_RATE
            flicker(player.Character)
            if ghostModel and ghostModel.Parent then flicker(ghostModel) end
        end
    end

    G.setActive = function(on)
        G.active = on
        G.nextEnsureAt, G.nextFlickerAt = 0, 0
        if on then
            G.update()
        else
            removeFrom(player.Character)
            removeFrom(ghostModel)
        end
    end

    G.cleanup = function()
        G.active = false
        if G.conn then G.conn:Disconnect() G.conn = nil end
        removeFrom(player.Character)
        removeFrom(ghostModel)
    end

    G.conn = RunService.Heartbeat:Connect(G.update)
end

------------------------------------------------------------------
-- MODES (M): each mode sets the colours, the text + font (move list title and the name above
-- your head) and its own theme song. All moves are the same in every mode for now.
------------------------------------------------------------------
-- switch the song: the old one fades out, the new one loads and fades in
CONFIG.THEME.play = function(file)
    local T = CONFIG.THEME
    if file then T.FILE = file end
    T.stop(true)
    T.start()
end

-- very dark text gets a light outline so it can still be read (black text on a dark box)
CONFIG.MODES.contrast = function(label, color, normalTransparency, normalStroke)
    local luminance = color.R * 0.299 + color.G * 0.587 + color.B * 0.114
    if luminance < 0.2 then
        label.TextStrokeColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.25
    else
        label.TextStrokeColor3 = normalStroke
        label.TextStrokeTransparency = normalTransparency
    end
end

CONFIG.MODES.playSwitchSound = function()
    local M = CONFIG.MODES
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(M.SWITCH_SOUND)
    sound.Volume = M.SWITCH_VOLUME
    sound.Parent = game:GetService("SoundService")
    sound.Ended:Connect(function() sound:Destroy() end)
    sound:Play()
    task.delay(15, function() if sound.Parent then sound:Destroy() end end)
end

CONFIG.MODES.apply = function(index, silent)
    local M = CONFIG.MODES
    local mode = M.list[index]
    if not mode then return end
    M.index = index

    -- colours (rainbow modes drive both colours from the rainbow instead)
    if mode.rainbow then
        rainbow.pulse, rainbow.muzzle = true, true
    else
        rainbow.pulse, rainbow.muzzle = false, false
        colors.pulse, colors.muzzle = mode.cylinder, mode.tip
    end
    refreshColor("pulse")
    refreshColor("muzzle")
    CONFIG.FX.loudnessColor = mode.loudnessColor == true -- visualizer goes black -> gray -> white with the song's loudness
    CONFIG.FX.strength = mode.visualizerStrength or CONFIG.VISUALIZER.STRENGTH -- this mode's own visualizer strength
    CONFIG.FX.shadeFlicker = mode.godCat == true -- God Cat: visualizer flickers through shades of black and white
    CONFIG.GODCAT.setActive(mode.godCat == true) -- God Cat: horns on the body / clone

    -- idle animations + patterns, and animations to replace (the tracks are swapped in the background)
    CONFIG.IDLE.setSpecs(mode)
    CONFIG.IDLE.rebuild()
    CONFIG.MOVEANIM.rebuild()
    CONFIG.REPLACE.setMap(mode.replace)

    -- revolver <-> this mode's gun (hidden/shown, muzzle moved to the gun's tip)
    if CONFIG.GUNS and CONFIG.GUNS.refresh then CONFIG.GUNS.refresh() end

    -- text + font: move list title and the name above the character
    if MovesBox.title then MovesBox.title.Text, MovesBox.title.Font = mode.text, mode.font end
    if MovesBox.tagLabel then MovesBox.tagLabel.Text, MovesBox.tagLabel.Font = mode.text, mode.font end
    if MovesBox.moves then
        for _, line in ipairs(MovesBox.moves) do
            line.Font = M.MOVE_LINES_USE_FONT and mode.font or Enum.Font.Arcade
        end
    end

    if not silent then M.playSwitchSound() end
    CONFIG.THEME.play(mode.song)
end

CONFIG.MODES.next = function()
    local M = CONFIG.MODES
    if deleted then return end
    M.apply(M.index % #M.list + 1, false)
end

------------------------------------------------------------------
-- DELETE / CLEANUP
------------------------------------------------------------------
deleteAll = function()
    if deleted then return end
    deleted = true
    CONFIG.HIDE.restoreAll()
    if connection then connection:Disconnect() connection = nil end
    if charConn then charConn:Disconnect() charConn = nil end
    if inputConn then inputConn:Disconnect() inputConn = nil end
    if ghostInputEndedConn then ghostInputEndedConn:Disconnect() ghostInputEndedConn = nil end
    if cooldownDeathConnection then cooldownDeathConnection:Disconnect() cooldownDeathConnection = nil end
    resetToolCooldown()
    finishDiagnosticWatch("Script unloaded")
    animationVoidTrip = nil
    CONFIG.FLOW.active, CONFIG.FLOW.fired, CONFIG.FLOW.destination = false, false, nil
    CONFIG.FLING.reset()
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = ORBIT_TOOL_NAME
    if voidReferenceConnection then voidReferenceConnection:Disconnect() voidReferenceConnection = nil end
    orbitEnabled = false
    shotTargetModel, shotReturnCFrame, ghostWorldCF = nil, nil, nil
    release(false)
    if orbitConnection then orbitConnection:Disconnect() orbitConnection = nil end
    if characterConnection2 then characterConnection2:Disconnect() characterConnection2 = nil end
    if diagnosticConnection then diagnosticConnection:Disconnect() diagnosticConnection = nil end
    if ghostRenderConnection then ghostRenderConnection:Disconnect() ghostRenderConnection = nil end
    AV.cleanup()
    destroyGhost()
    local char = player.Character
    if char then
        for _, descendant in ipairs(char:GetDescendants()) do
            if descendant:IsA("BasePart") then descendant.LocalTransparencyModifier = 0 end
        end
    end
    clearAnimations()
    removeModel()
    if gui then gui:Destroy() gui = nil panel = nil visibilityButton = nil end
    if MovesBox.conn then MovesBox.conn:Disconnect() MovesBox.conn = nil end
    if MovesBox.gui then MovesBox.gui:Destroy() MovesBox.gui = nil end
    if MovesBox.tag then MovesBox.tag:Destroy() MovesBox.tag = nil end
    CONFIG.THEME.stop(true)
    CONFIG.DELETE.restoreAll()
    CONFIG.GODCAT.cleanup()
    if CONFIG.REPLACE.conn then CONFIG.REPLACE.conn:Disconnect() CONFIG.REPLACE.conn = nil end
    CONFIG.FX.destroy()
    if Perf.reportConn then Perf.reportConn:Disconnect() Perf.reportConn = nil end
end

------------------------------------------------------------------
-- STARTUP / INPUT / RESPAWN
------------------------------------------------------------------
buildUI()
buildMovesBox()
CONFIG.MODES.apply(CONFIG.MODES.index, true) -- sets the colours/text/font of the first mode and starts its song
if not player.Character then player.CharacterAdded:Wait() end
task.wait(0.5)
attach()
inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if ghostMoveKeys[input.KeyCode] ~= nil and not UserInputService:GetFocusedTextBox() then
        ghostMoveKeys[input.KeyCode] = true
    end
    if gameProcessed then return end
    if CONFIG.PROFILE and input.KeyCode == Enum.KeyCode.P and not UserInputService:GetFocusedTextBox() then
        -- each press: remove the ghost and rebuild it with the next test stage (6 stages, then off)
        Perf.stageIndex = (Perf.stageIndex or 0) + 1
        if Perf.stageIndex > #Perf.STAGES then Perf.stageIndex = 0 end
        Perf.stage = Perf.STAGES[Perf.stageIndex]
        Perf.testGhost = Perf.stage ~= nil
        destroyGhost(false)
        print("[PulseRevolver][perf] GHOST TEST STAGE -> " .. (Perf.stage and Perf.stage.name or "OFF"))
        return
    end
    if ghostModel and not UserInputService:GetFocusedTextBox() then
        if ghostMoveKeys[input.KeyCode] ~= nil then return
        elseif input.KeyCode == Enum.KeyCode.Space and ghostHumanoid then ghostHumanoid.Jump = true return end
    end
    if input.KeyCode == Enum.KeyCode.T then teleportToCursor()
    elseif input.KeyCode == CONFIG.TAUNT_KEY then startTaunt()
    elseif input.KeyCode == CONFIG.SHOOT_KEY then startShoot()
    elseif input.KeyCode == CONFIG.FLOWING_KEY then CONFIG.FLOW.start()
    elseif input.KeyCode == CONFIG.FLING.KEY then CONFIG.FLING.start()
    elseif input.KeyCode == CONFIG.DELETE.KEY then CONFIG.DELETE.start()
    elseif input.KeyCode == CONFIG.ATTACK.KEY then CONFIG.ATTACK.cycle()
    elseif input.KeyCode == CONFIG.BRING.KEY then CONFIG.BRING.cycle()
    elseif input.KeyCode == CONFIG.MODES.SWITCH_KEY then CONFIG.MODES.next() end
end)
ghostInputEndedConn = UserInputService.InputEnded:Connect(function(input)
    if ghostMoveKeys[input.KeyCode] ~= nil then ghostMoveKeys[input.KeyCode] = false end
end)
charConn = player.CharacterAdded:Connect(function()
    if deleted then return end
    resetToolCooldown()
    finishDiagnosticWatch("Local character respawned; monitor reset")
    animationVoidTrip = nil
    if voidReferenceConnection then voidReferenceConnection:Disconnect() voidReferenceConnection = nil end
    orbitEnabled = false
    CONFIG.FLOW.active, CONFIG.FLOW.fired, CONFIG.FLOW.destination = false, false, nil
    CONFIG.FLOW.toolWarned = false
    CONFIG.FLOW.toolName = ORBIT_TOOL_NAME
    shotTargetModel, shotReturnCFrame, ghostWorldCF = nil, nil, nil
    ghostBuildRetryAt = 0
    release(false)
    destroyGhost()
    task.wait(0.5)
    if not deleted then attach() end
end)
