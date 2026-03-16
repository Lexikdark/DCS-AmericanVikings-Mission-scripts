---------------------------------------------------------------------
-- RedCoalitionLock.lua
-- Prevents players from occupying any Red coalition slots.
-- Works by periodically scanning all connected players and forcing
-- anyone found on the Red side (coalition 1) back to Spectators.
--
-- LOAD ORDER: DO SCRIPT FILE at Mission Start (no dependencies).
-- NOTE: net.* functions only work on a multiplayer server.
--       In single-player / ME preview the checks are silently skipped.
---------------------------------------------------------------------

local RED_COALITION    = 1        -- DCS coalition ID for Red
local CHECK_INTERVAL   = 5        -- seconds between enforcement scans
local KICK_MESSAGE     = "[SERVER] Red coalition is reserved for AI only. You have been moved to Spectators."

---------------------------------------------------------------------
-- ENFORCEMENT LOOP
---------------------------------------------------------------------

local function enforceRedLock()
    -- net library is only present in multiplayer; skip gracefully otherwise
    if not net or not net.get_player_list then
        return timer.getTime() + CHECK_INTERVAL
    end

    local players = net.get_player_list()
    for _, pid in ipairs(players) do
        -- pid 1 is always the server/host process itself — never touch it
        if pid ~= 1 then
            local info = net.get_player_info(pid)
            if info and info.side == RED_COALITION then
                -- Force player to spectators (coalition 0, slot "")
                net.force_player_slot(pid, 0, "")
                net.send_chat_to(KICK_MESSAGE, pid)
                env.info("[RedLock] Player '" .. tostring(info.name) ..
                         "' removed from Red slot '" .. tostring(info.slot) .. "' → Spectators.")
            end
        end
    end

    return timer.getTime() + CHECK_INTERVAL
end

---------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------

-- Start the first check 10 s after mission load to allow everything
-- to initialise, then repeat every CHECK_INTERVAL seconds.
timer.scheduleFunction(enforceRedLock, nil, timer.getTime() + 10)
env.info("[RedLock] RedCoalitionLock loaded. Red slots locked to AI only.")
