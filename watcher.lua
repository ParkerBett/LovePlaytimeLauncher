local workDir, exePath = ...

local cmd = string.format('start "" /WAIT /D "%s" "%s"', workDir, exePath)
os.execute(cmd)

love.thread.getChannel("game_closed"):push(true)
