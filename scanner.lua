local parentDir = ...

local CHAPTER_BINARIES = {
    ["poppy_playtime-win64-shipping.exe"] = { chapter = 1, title = "Chapter 1: A Tight Squeeze" },
    ["ch2_pro-win64-shipping.exe"] = { chapter = 2, title = "Chapter 2: Fly in a Web" },
    ["playtime_prototype4-win64-shipping.exe"] = { chapter = 2, title = "Chapter 2: Fly in a Web (Legacy)" },
    ["playtime_chapter3-win64-shipping.exe"] = { chapter = 3, title = "Chapter 3: Deep Sleep" },
    ["ch4_pro-win64-shipping.exe"] = { chapter = 4, title = "Chapter 4: Safe Haven" },
    ["ch5_pro-win64-shipping.exe"] = { chapter = 5, title = "Chapter 5: Broken Things" }
}

local found = {}
local cmd = string.format('dir "%s\\*-Win64-Shipping.exe" /s /b 2>nul', parentDir)
local handle = io.popen(cmd)

if handle then
    for fullPath in handle:lines() do
        local exeName = fullPath:match("([^\\]+)$")
        if exeName then
            local match = CHAPTER_BINARIES[exeName:lower()]
            if match then
                found[match.chapter] = {
                    chapter = match.chapter,
                    title = match.title,
                    exe = exeName,
                    path = fullPath
                }
            end
        end
    end
    handle:close()
end

love.thread.getChannel("scan_results"):push(found)
