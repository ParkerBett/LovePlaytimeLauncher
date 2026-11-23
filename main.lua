local mob_splash
local playtime_vibes
local hover_sfx
local press_sfx
local background
local splash_finished = false
local music_started = false
local scaleX, scaleY
local bg_alpha = 0
local fade_duration = 1.5

local activeBgIndex = nil   -- chapter whose background is currently showing
local columnZone = nil      -- rectangle covering all buttons plus the gaps between

local chapterBgs = {}       -- [i] = { img = Image, alpha = 0 }
local BG_FADE_SPEED = 4     -- higher = faster crossfade

local installedChapters = {}
local statusText = "Scanning for chapters..."

-- Chapter buttons -------------------------------------------------------
local CHAPTER_COUNT = 5
local LAYOUT = {
    startX = 40,
    startY = 30,
    gapY = 15,
    scale = 0.6,       -- 1.0 = original size; lower = smaller
    bottomMargin = 50, -- keeps room for the status text
}
local chapterButtons = {}

local scanThread
local scanDone = false
local grayscaleShader

local function getParentDirectory()
    local base = love.filesystem.getSourceBaseDirectory():gsub("/", "\\")
    return base:match("^(.*)\\[^\\]+$") or (base .. "\\..")
end

local isPlayingChapter = false

local function launchChapter(chapterData)
    if not chapterData or isPlayingChapter then return end
    isPlayingChapter = true

    local workDir = chapterData.path:match("^(.*)\\[^\\]+$")
    statusText = "Playing " .. chapterData.title .. "..."

    local watchThread = love.thread.newThread("watcher.lua")
    watchThread:start(workDir, chapterData.path)

    love.window.minimize()
end

local function finishSplash()
    if not splash_finished then
        mob_splash:release()
        splash_finished = true
    end
end

local function loadChapterButtons()
    local fallbackW, fallbackH = 300, 170 -- used if a banner image is missing

    -- Load images and record their natural sizes
    for i = 1, CHAPTER_COUNT do
        local path = string.format("assets/banners/chapter_%d.jpg", i)
        local btn = { index = i, isHovered = false }

        if love.filesystem.getInfo(path) then
            btn.img = love.graphics.newImage(path)
            btn.naturalW = btn.img:getWidth()
            btn.naturalH = btn.img:getHeight()
            if i == 1 then fallbackW, fallbackH = btn.naturalW, btn.naturalH end
        end

        chapterButtons[i] = btn
    end

    for _, btn in ipairs(chapterButtons) do
        btn.naturalW = btn.naturalW or fallbackW
        btn.naturalH = btn.naturalH or fallbackH
    end

    -- Shrink further if the column wouldn't fit in the window
    local totalNaturalH = 0
    for _, btn in ipairs(chapterButtons) do
        totalNaturalH = totalNaturalH + btn.naturalH
    end
    local availableH = love.graphics.getHeight() - LAYOUT.startY - LAYOUT.bottomMargin
                       - LAYOUT.gapY * (CHAPTER_COUNT - 1)
    local scale = math.min(LAYOUT.scale, availableH / totalNaturalH)

    -- Stack them in one column on the left
    local y = LAYOUT.startY
    for _, btn in ipairs(chapterButtons) do
        btn.scale = scale
        btn.width = btn.naturalW * scale
        btn.height = btn.naturalH * scale
        btn.x = LAYOUT.startX
        btn.y = y
        y = y + btn.height + LAYOUT.gapY
    end

    -- Zone covering the whole column, gaps included
    local maxW = 0
    for _, btn in ipairs(chapterButtons) do
        maxW = math.max(maxW, btn.width)
    end
    columnZone = {
        x = LAYOUT.startX,
        y = LAYOUT.startY,
        w = maxW,
        h = (y - LAYOUT.gapY) - LAYOUT.startY, -- y includes one extra trailing gap
    }
end

local function drawChapterButton(btn)
    local installed = installedChapters[btn.index] ~= nil

    if btn.img then
        if not installed then
            love.graphics.setColor(0.4, 0.4, 0.4, 1)
            love.graphics.draw(btn.img, btn.x, btn.y, 0, btn.scale, btn.scale)
        elseif btn.isHovered then
            love.graphics.setShader(grayscaleShader)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(btn.img, btn.x, btn.y, 0, btn.scale, btn.scale)
            love.graphics.setShader()
        else
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(btn.img, btn.x, btn.y, 0, btn.scale, btn.scale)
        end
    else
        local shade = installed and (btn.isHovered and 0.5 or 0.3) or 0.15
        love.graphics.setColor(shade, shade, shade, 1)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height)
        love.graphics.setColor(1, 1, 1, installed and 1 or 0.5)
        love.graphics.printf("Chapter " .. btn.index, btn.x,
            btn.y + btn.height / 2 - 8, btn.width, "center")
    end
end

function love.load()
    love.window.setTitle("Playtime Launcher")
    love.graphics.setFont(love.graphics.newFont(16))

    grayscaleShader = love.graphics.newShader[[
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 pixel = Texel(texture, texture_coords) * color;
            float gray = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
            return vec4(gray, gray, gray, pixel.a);
        }
    ]]

    loadChapterButtons()

    for i = 1, CHAPTER_COUNT do
        local path = string.format("assets/backgrounds/chapter_%d.png", i)
        if love.filesystem.getInfo(path) then
            chapterBgs[i] = { img = love.graphics.newImage(path), alpha = 0 }
        end
    end

    mob_splash = love.graphics.newVideo("assets/videos/mob_splash.ogv")
    playtime_vibes = love.audio.newSource("assets/audio/theme.mp3", "stream")
    hover_sfx = love.audio.newSource("assets/audio/hover.mp3", "static")
    press_sfx = love.audio.newSource("assets/audio/press.mp3", "static")
    background = love.graphics.newImage("assets/backgrounds/main.jpg")

    scaleX = love.graphics.getWidth() / mob_splash:getWidth()
    scaleY = love.graphics.getHeight() / mob_splash:getHeight()

    local parentDir = getParentDirectory()
    scanThread = love.thread.newThread("scanner.lua")
    scanThread:start(parentDir)

    mob_splash:play()
end

function love.focus(focused)
    if not music_started then return end

    if focused then
        playtime_vibes:play()
    else
        playtime_vibes:pause()
    end
end

function love.keypressed(key)
    if not splash_finished then
        if key == "space" or key == "return" or key == "escape" then
            finishSplash()
        end
        return
    end

    local num = tonumber(key)
    local num = tonumber(key)
    if num and installedChapters[num] then
        press_sfx:stop()
        press_sfx:play()
        launchChapter(installedChapters[num])
    end
end

function love.update(dt)
    if not scanDone then
        local results = love.thread.getChannel("scan_results"):pop()
        if results then
            installedChapters = results
            scanDone = true

            local count = 0
            for _ in pairs(installedChapters) do
                count = count + 1
            end
            if count == 1 then
                statusText = string.format("Scan complete (%d chapter found)", count)
            elseif count >= 1 then
                statusText = string.format("Scan complete (%d chapters found)", count)
            end
        end
    end

    if not splash_finished and not mob_splash:isPlaying() then
        finishSplash()
    end

    if splash_finished then
        if bg_alpha < 1 then
            bg_alpha = math.min(1, bg_alpha + (dt / fade_duration))
        end
        if not music_started then
            playtime_vibes:setLooping(true)
            playtime_vibes:play()
            music_started = true
        end
    end

    local mx, my = love.mouse.getPosition()
    for _, btn in ipairs(chapterButtons) do
        local wasHovered = btn.isHovered
        btn.isHovered = mx >= btn.x and mx <= btn.x + btn.width
                    and my >= btn.y and my <= btn.y + btn.height

        -- Play only on the frame the cursor enters the button
        if splash_finished and btn.isHovered and not wasHovered
        and installedChapters[btn.index] then
            hover_sfx:stop()
            hover_sfx:play()
        end
    end

    -- Decide which chapter background should be showing
    local hoveredIndex = nil
    for _, btn in ipairs(chapterButtons) do
        if btn.isHovered then
            hoveredIndex = btn.index
            break
        end
    end

    if hoveredIndex then
        activeBgIndex = hoveredIndex
    elseif activeBgIndex then
        -- Not on a button: keep the current background while in the gaps,
        -- clear it only once the cursor leaves the column
        local inColumn = mx >= columnZone.x and mx <= columnZone.x + columnZone.w
                    and my >= columnZone.y and my <= columnZone.y + columnZone.h
        if not inColumn then
            activeBgIndex = nil
        end
    end

    -- Fade chapter backgrounds
    local step = dt * BG_FADE_SPEED
    local active = activeBgIndex and chapterBgs[activeBgIndex]

    for i, bg in pairs(chapterBgs) do
        if i == activeBgIndex then
            -- Incoming background fades in
            bg.alpha = math.min(1, bg.alpha + step)
        elseif active then
            -- Another chapter is taking over: stay opaque underneath
            -- until the new one is fully visible, then drop out
            if active.alpha >= 1 then
                bg.alpha = 0
            end
        else
            -- No chapter active (or it has no image): fade back to main
            bg.alpha = math.max(0, bg.alpha - step)
        end
    end

    if isPlayingChapter and love.thread.getChannel("game_closed"):pop() then
        isPlayingChapter = false
        love.window.restore()
        statusText = "Ready"
    end
end

function love.draw()
    if not splash_finished then
        if mob_splash:tell() > 0 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(mob_splash, 0, 0, 0, scaleX, scaleY)
        end
    else
        love.graphics.setColor(1, 1, 1, bg_alpha)
        love.graphics.draw(background, 0, 0, 0, 1.44, 1.44)

    -- Draw outgoing backgrounds first, the active one on top
    local function drawChapterBg(bg)
        if bg and bg.alpha > 0 then
            love.graphics.setColor(1, 1, 1, bg.alpha * bg_alpha)
            love.graphics.draw(bg.img, 0, 0, 0,
                love.graphics.getWidth() / bg.img:getWidth(),
                love.graphics.getHeight() / bg.img:getHeight())
        end
    end

    for i = 1, CHAPTER_COUNT do
        if i ~= activeBgIndex then
            drawChapterBg(chapterBgs[i])
        end
    end
    if activeBgIndex then
        drawChapterBg(chapterBgs[activeBgIndex])
    end

        for _, btn in ipairs(chapterButtons) do
            drawChapterButton(btn)
        end

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(statusText, 20, love.graphics.getHeight() - 35)
    end
end

function love.mousepressed(x, y, mouseButton)
    if not (splash_finished and mouseButton == 1) then return end

    for _, btn in ipairs(chapterButtons) do
        if btn.isHovered then
            if installedChapters[btn.index] then
                press_sfx:stop()
                press_sfx:play()
                launchChapter(installedChapters[btn.index])
            else
                statusText = string.format("Chapter %d is not installed.", btn.index)
            end
            return
        end
    end
end