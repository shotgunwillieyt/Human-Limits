-- Human Limits v0.2.4: repeatable sleep deprivation blackout (Build 42.21)
-- Reads vanilla FATIGUE (0..1; higher is worse). Does not modify fatigue.
-- Warns at 0.85, starts a timer at 0.95, and attempts a brief forced-sleep blackout
-- after 30 continuous in-game minutes at/above 0.95. Requires live game testing.
HumanLimits = HumanLimits or {}
HumanLimits.SleepDeprivation = HumanLimits.SleepDeprivation or {}
local SD = HumanLimits.SleepDeprivation
SD.version = "0.2.4"
SD.warningThreshold = 0.85
SD.collapseThreshold = 0.95
SD.collapseDelayHours = 0.5       -- 30 in-game minutes at critical fatigue
SD.blackoutDurationSeconds = 5 -- five real-world seconds of forced sleep
SD.states = SD.states or {}
SD.warnedMissingFatigue = false

local function log(message)
    if HumanLimits.log then HumanLimits.log("[SleepDeprivation] " .. tostring(message))
    else print("[HumanLimits][SleepDeprivation] " .. tostring(message)) end
end
local function worldHours()
    local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and type(value) == "number" then return value end
    return nil
end
local function readFatigue(player)
    if not CharacterStat or CharacterStat.FATIGUE == nil then
        if not SD.warnedMissingFatigue then SD.warnedMissingFatigue = true; log("WARNING: CharacterStat.FATIGUE unavailable; module inactive.") end
        return nil
    end
    local okStats, stats = pcall(function() return player:getStats() end)
    if not okStats or not stats then return nil end
    local okValue, value = pcall(function() return stats:get(CharacterStat.FATIGUE) end)
    if not okValue or type(value) ~= "number" then
        if not SD.warnedMissingFatigue then SD.warnedMissingFatigue = true; log("WARNING: could not read fatigue; module inactive.") end
        return nil
    end
    -- FATIGUE is expected to be normalized 0..1 in Build 42.
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return value
end
local function say(player, message)
    local ok, err = pcall(function() player:Say(message) end)
    if not ok then log("Speech bubble failed: " .. tostring(err)) end
    log("Thought: " .. message)
end
local function isAsleep(player)
    local ok, value = pcall(function() return player:isAsleep() end)
    return ok and value == true
end
local function attemptBlackout(player, state, now)
    -- Set a wake deadline before initiating the state change so an API failure is diagnosable.
    state.blackoutWakeAtReal = os.time() + SD.blackoutDurationSeconds
    local ok, err = pcall(function()
        player:setAsleep(true)
    end)
    if not ok then
        state.blackoutWakeAtReal = nil
        log("ERROR: setAsleep(true) failed; blackout not applied: " .. tostring(err))
        return false
    end
    state.collapseAt = nil
    state.warningShown = false
    state.lastBlackoutAt = now
    log("BLACKOUT STARTED at fatigue threshold; intended duration 5 real-world seconds.")
    return true
end
function HumanLimits.onSleepDeprivationPlayerUpdate(player)
    if not player then return end
    local localPlayer = getPlayer()
    if localPlayer and player ~= localPlayer then return end
    local okDead, dead = pcall(function() return player:isDead() end)
    if okDead and dead then SD.states[player] = nil; return end
    local now = worldHours()
    if not now then return end
    local state = SD.states[player]
    if not state then
        state = { collapseAt = nil, warningShown = false, blackoutWakeAtReal = nil, lastBlackoutAt = nil }
        SD.states[player] = state
        log("Sleep-deprivation tracker initialized.")
    end
    local asleep = isAsleep(player)
    if state.blackoutWakeAtReal then
        if asleep and os.time() >= state.blackoutWakeAtReal then
            local ok, err = pcall(function() player:forceAwake() end)
            if ok then
                state.blackoutWakeAtReal = nil
                state.collapseAt = nil
                log("BLACKOUT ENDED after 5 real seconds; forceAwake succeeded. Critical-fatigue timer may start a new cycle.")
            else
                log("ERROR: forceAwake failed at blackout deadline: " .. tostring(err))
            end
        elseif not asleep then
            -- If vanilla or another mod wakes the player first, do not force another wake.
            state.blackoutWakeAtReal = nil
            state.collapseAt = nil
            log("Blackout ended early because player is already awake; critical-fatigue timer reset for next cycle.")
        end
        return
    end
    if asleep then
        -- Do not initiate a blackout while the player is already sleeping normally.
        state.collapseAt = nil
        return
    end
    local fatigue = readFatigue(player)
    if fatigue == nil then return end
    if fatigue < SD.warningThreshold then
        state.warningShown = false
        state.collapseAt = nil
        return
    end
    if not state.warningShown then
        say(player, "I can barely keep my eyes open...")
        state.warningShown = true
        log(string.format("Warning thought shown at fatigue %.1f%%.", fatigue * 100))
    end
    if fatigue >= SD.collapseThreshold then
        if not state.collapseAt then
            state.collapseAt = now
            log(string.format("Critical fatigue timer started at %.1f%%.", fatigue * 100))
        elseif (now - state.collapseAt) >= SD.collapseDelayHours then
            -- Repeat after each fresh 30-minute critical-fatigue interval if fatigue remains high.
            say(player, "I... can't stay awake...")
            attemptBlackout(player, state, now)
        end
    else
        if state.collapseAt then log("Critical fatigue timer reset; fatigue fell below 95%.") end
        state.collapseAt = nil
    end
end
Events.OnPlayerUpdate.Add(HumanLimits.onSleepDeprivationPlayerUpdate)
log(string.format("Sleep-deprivation module v%s loaded. Warning %.0f%%; collapse threshold %.0f%% for %.0f in-game minutes; blackout duration %.0f real seconds.", SD.version, SD.warningThreshold*100, SD.collapseThreshold*100, SD.collapseDelayHours*60, SD.blackoutDurationSeconds))
