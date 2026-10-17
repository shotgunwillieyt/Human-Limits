-- Human Limits Build 42 core bootstrap v0.2.9
-- Panic must stay strictly above 70% for 60 continuous in-game minutes.
-- Explicit reset diagnostics; final warning allows at least 5 real seconds.
HumanLimits = HumanLimits or {}
HumanLimits.version = "0.2.9"
HumanLimits.loaded = false
HumanLimits.PanicFatal = HumanLimits.PanicFatal or {}
local HF = HumanLimits.PanicFatal
HF.threshold = 0.70
HF.durationHours = 1.0
HF.finalWarningLeadHours = 5 / 3600 -- show warning about 5 in-game seconds before deadline
HF.finalWarningGraceSeconds = 5 -- minimum real seconds to react
HF.startedAt = {}
HF.killed = {}
HF.notices = {}
HF.finalWarningAtReal = {}
HF.lastPanic = {}
HF.calmMessageShown = {}
HF.warnedMissingPanic = false

function HumanLimits.log(message) print("[HumanLimits] " .. tostring(message)) end
local function getWorldHours()
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and type(hours) == "number" then return hours end
    return nil
end
local function readPanic(player)
    local okStats, stats = pcall(function() return player:getStats() end)
    if not okStats or not stats or not CharacterStat or CharacterStat.PANIC == nil then return nil end
    local okValue, value = pcall(function() return stats:get(CharacterStat.PANIC) end)
    if not okValue or type(value) ~= "number" then return nil end
    -- Support either normalized 0..1 values or percent-style 0..100 values.
    if value > 1 then value = value / 100 end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return value
end
local function say(player, message)
    local ok, err = pcall(function() player:Say(message) end)
    if not ok then HumanLimits.log("Speech bubble failed: " .. tostring(err)) end
    HumanLimits.log("Thought: " .. message)
end
local function clearTimer(player, reason, panic)
    if HF.startedAt[player] ~= nil then
        HF.startedAt[player] = nil
        HF.notices[player] = nil
        HF.finalWarningAtReal[player] = nil
        HumanLimits.log(string.format("TIMER CANCELLED (%s). Panic=%.1f%%; old countdown discarded.", reason, panic * 100))
    end
end
local function killFromCardiacArrest(player)
    local ok, err = pcall(function() player:setHealth(0) end)
    HF.killed[player] = true
    if ok then
        say(player, "I... can't catch my breath...")
        HumanLimits.log("Panic timer expired; player:setHealth(0) call completed. Verify death in-game.")
    else
        say(player, "Something's seriously wrong... I can't breathe!")
        HumanLimits.log("ERROR: player:setHealth(0) failed: " .. tostring(err))
    end
end
function HumanLimits.onPanicFatalPlayerUpdate(player)
    if not player then return end
    local localPlayer = getPlayer()
    if localPlayer and player ~= localPlayer then return end
    if HF.killed[player] then return end
    local dead = false
    pcall(function() dead = player:isDead() end)
    if dead then return end
    local panic = readPanic(player)
    if panic == nil then
        if not HF.warnedMissingPanic then HF.warnedMissingPanic = true; HumanLimits.log("WARNING: could not read panic stat; mechanic inactive.") end
        return
    end
    local now = getWorldHours()
    if not now then return end
    local previous = HF.lastPanic[player]
    HF.lastPanic[player] = panic

    -- Calm thought only on a genuine downward crossing of 35%, not on load.
    if previous ~= nil and previous >= 0.35 and panic < 0.35 and not HF.calmMessageShown[player] then
        say(player, "Okay... breathe. I think I'm settling down.")
        HF.calmMessageShown[player] = true
    elseif panic >= 0.35 then
        HF.calmMessageShown[player] = nil
    end

    if panic > HF.threshold then
        if HF.startedAt[player] == nil then
            HF.startedAt[player] = now
            HF.notices[player] = { [20] = false, [40] = false, [50] = false, final = false }
            HF.finalWarningAtReal[player] = nil
            say(player, "Man... my chest feels tight.")
            HumanLimits.log(string.format("TIMER STARTED: panic %.1f%% > 70%% at world age %.4f hours.", panic * 100, now))
            return
        end
        local elapsed = now - HF.startedAt[player]
        local minutes = elapsed * 60
        local notices = HF.notices[player] or { [20] = false, [40] = false, [50] = false, final = false }
        if minutes >= 20 and not notices[20] then say(player, "Ugh... why am I having trouble breathing?"); notices[20] = true end
        if minutes >= 40 and not notices[40] then say(player, "I need to get somewhere safe..."); notices[40] = true end
        if minutes >= 50 and not notices[50] then say(player, "My heart's pounding... I can't calm down."); notices[50] = true end
        local finalWarningAt = HF.durationHours - HF.finalWarningLeadHours
        if elapsed >= finalWarningAt and not notices.final then
            say(player, "No... something's really wrong. I need help... NOW!")
            notices.final = true
            HF.finalWarningAtReal[player] = os.time()
            HumanLimits.log("FINAL WARNING shown; will not kill until deadline reached and at least 5 real seconds have elapsed.")
        end
        HF.notices[player] = notices
        if elapsed >= HF.durationHours and notices.final and HF.finalWarningAtReal[player] and (os.time() - HF.finalWarningAtReal[player]) >= HF.finalWarningGraceSeconds then
            killFromCardiacArrest(player)
        end
    else
        -- <=70% always cancels the active countdown, regardless of elapsed time.
        clearTimer(player, "panic <= 70%", panic)
    end
end
local function onGameStart()
    if HumanLimits.loaded then return end
    HumanLimits.loaded = true
    HumanLimits.log("Loaded successfully. Version " .. tostring(HumanLimits.version))
    HumanLimits.log("Rule: panic >70% for 60 continuous in-game minutes; <=70% cancels immediately.")
    HumanLimits.log("Smoker sleep interruption module is loaded separately.")
end
Events.OnGameStart.Add(onGameStart)
Events.OnPlayerUpdate.Add(HumanLimits.onPanicFatalPlayerUpdate)
