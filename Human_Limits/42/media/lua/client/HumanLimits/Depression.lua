-- Human Limits v0.2.11: chance-based depression breakdowns and thought variation (Build 42.21)
-- Uses vanilla unhappiness as a provisional signal. Breakdown chance begins at 70 and rises to 100%.
-- Non-lethal episode: drops held items, attempts the previously tested posture variables, and briefly locks movement.
HumanLimits = HumanLimits or {}
HumanLimits.Depression = HumanLimits.Depression or {}
local DP = HumanLimits.Depression
DP.version = "0.2.11"
DP.threshold = 70
DP.escalationHours = 1.0          -- at 100 unhappiness, guarantee an episode after one continuous qualifying hour
DP.rollIntervalHours = 1.0 / 6.0 -- make a chance roll every 10 in-game minutes
DP.episodeSeconds = 10            -- real-world episode duration
DP.ambientThoughtIntervalSeconds = 30
DP.states = DP.states or {}
DP.lastWarnedApi = false

local function log(msg)
    if HumanLimits.log then HumanLimits.log("[Depression] " .. tostring(msg)) else print("[HumanLimits][Depression] " .. tostring(msg)) end
end
local function nowHours()
    local ok, v = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and type(v) == "number" then return v end
end
local function say(p, msg)
    local ok, err = pcall(function() p:Say(msg) end)
    if not ok then log("Speech bubble failed: " .. tostring(err)) end
end
local function readUnhappiness(p)
    if not CharacterStat or CharacterStat.UNHAPPINESS == nil then
        if not DP.lastWarnedApi then DP.lastWarnedApi = true; log("WARNING: CharacterStat.UNHAPPINESS is unavailable; breakdown inactive.") end
        return nil
    end
    local okStats, stats = pcall(function() return p:getStats() end)
    if not okStats or not stats then
        if not DP.lastWarnedApi then DP.lastWarnedApi = true; log("WARNING: couldn't read player stats; breakdown inactive.") end
        return nil
    end
    local ok, v = pcall(function() return stats:get(CharacterStat.UNHAPPINESS) end)
    if not ok or type(v) ~= "number" then
        if not DP.lastWarnedApi then DP.lastWarnedApi = true; log("WARNING: stats:get(CharacterStat.UNHAPPINESS) failed; breakdown inactive.") end
        return nil
    end
    if v >= 0 and v <= 1 then v = v * 100 end
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    return v
end
local function isDead(p)
    local ok, v = pcall(function() return p:isDead() end)
    return ok and v == true
end
local function dropHandItem(p, which)
    local item
    local okGet = pcall(function()
        if which == "primary" then item = p:getPrimaryHandItem() else item = p:getSecondaryHandItem() end
    end)
    if not okGet or not item then return false end
    local square
    local okSquare = pcall(function() square = p:getCurrentSquare() end)
    if not okSquare or not square then log("Could not drop " .. which .. " hand item: no current square."); return false end
    local okDrop, err = pcall(function()
        local inv = p:getInventory()
        inv:Remove(item)
        square:AddWorldInventoryItem(item, 0.5, 0.5, 0)
        if which == "primary" then p:setPrimaryHandItem(nil) else p:setSecondaryHandItem(nil) end
    end)
    if not okDrop then log("Item drop failed for " .. which .. " hand: " .. tostring(err)); return false end
    log("Dropped " .. which .. " hand item as breakdown began.")
    return true
end

local function pickThought(list)
    local idx
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(#list) end)
        if ok and type(value) == "number" then idx = value + 1 end
    end
    if not idx then idx = math.random(#list) end
    return list[idx]
end

local function breakdownChance(unhappiness)
    -- Per-roll probability curve. A roll occurs every 10 in-game minutes while unhappiness >= 70.
    -- Values are intentionally stepped to make severity progression easy to tune and explain.
    if unhappiness < 70 then return 0 end
    if unhappiness < 75 then return 5 end
    if unhappiness < 80 then return 10 end
    if unhappiness < 85 then return 20 end
    if unhappiness < 90 then return 35 end
    if unhappiness < 95 then return 50 end
    if unhappiness < 100 then return 75 end
    return 100
end

local function startEpisode(p, s, nowReal, unhappiness, chance, roll)
    s.episodeUntil = nowReal + DP.episodeSeconds
    s.started = true
    s.lastThought = nowReal
    dropHandItem(p, "primary")
    dropHandItem(p, "secondary")
    local crouchCalls = {}
    for _, variableName in ipairs({"isCrouch", "isCrouching"}) do
        local ok, err = pcall(function() p:setVariable(variableName, true) end)
        crouchCalls[#crouchCalls + 1] = variableName .. "=" .. tostring(ok)
        if not ok then log("Crouch variable " .. variableName .. " failed: " .. tostring(err)) end
    end
    local lockOK, lockErr = pcall(function() p:setBlockMovement(true) end)
    s.crouchApplied = true
    s.movementLocked = lockOK
    s.startedAtReal = nowReal
    local openingThoughts = {
        "I can't... I can't deal with this right now...",
        "It's all too much. I need a moment...",
        "I just can't keep it together right now...",
        "Please, make it stop... I need a second...",
        "I can't think straight... just leave me alone..."
    }
    say(p, pickThought(openingThoughts))
    log(string.format("BREAKDOWN STARTED: unhappiness=%.1f/100; chance=%.1f%%; roll=%.2f%%; intended duration=%d real seconds. animation setters: %s; movementLock=%s", unhappiness, chance, roll, DP.episodeSeconds, table.concat(crouchCalls, ", "), tostring(lockOK)))
    if not lockOK then log("Movement lock failed: " .. tostring(lockErr)) end
end

local function endEpisode(p, s)
    if s.movementLocked then
        local ok, err = pcall(function() p:setBlockMovement(false) end)
        if not ok then log("WARNING: movement unlock failed: " .. tostring(err)) end
    end
    if s.crouchApplied then
        for _, variableName in ipairs({"isCrouch", "isCrouching"}) do
            local ok, err = pcall(function() p:setVariable(variableName, false) end)
            if not ok then log("Crouch reset " .. variableName .. " failed: " .. tostring(err)) end
        end
    end
    local actualDuration = s.startedAtReal and (os.time() - s.startedAtReal) or -1
    s.episodeUntil = nil; s.started = false; s.movementLocked = false; s.crouchApplied = false
    s.lastThought = nil; s.startedAtReal = nil
    -- Every completed episode begins a fresh cycle; if unhappiness remains >=70, new rolls resume after 10 in-game minutes.
    s.severeSince = nowHours()
    s.nextRollAt = s.severeSince and (s.severeSince + DP.rollIntervalHours) or nil
    s.warningAt = os.time()
    s.nextAmbientThought = os.time() + DP.ambientThoughtIntervalSeconds
    say(p, pickThought({
        "...Okay. Just breathe. One thing at a time.",
        "...I need to pull myself together...",
        "...That was awful. Just keep going...",
        "...Okay... just get through the next minute."
    }))
    log("BREAKDOWN ENDED; measured real duration=" .. tostring(actualDuration) .. " seconds; controls released. Chance timer reset for the next episode.")
end

function HumanLimits.onDepressionPlayerUpdate(p)
    if not p then return end
    local localP = getPlayer()
    if localP and p ~= localP then return end
    if isDead(p) then DP.states[p] = nil; return end
    local nowH = nowHours(); if not nowH then return end
    local nowR = os.time()
    local s = DP.states[p]
    if not s then
        s = { severeSince = nil, nextRollAt = nil, episodeUntil = nil, started = false, warningAt = nil, nextAmbientThought = nil }
        DP.states[p] = s
        log("Depression tracker initialized.")
    end
    if s.episodeUntil then
        if nowR >= s.episodeUntil then
            endEpisode(p, s)
        elseif s.lastThought and nowR - s.lastThought >= 4 then
            local thoughts = {
                "I can't get my head straight...",
                "Everything feels impossible right now.",
                "Please... just let this pass.",
                "I don't know what to do anymore...",
                "I feel like I'm falling apart...",
                "I need everything to stop for a minute...",
                "I can't keep carrying all of this..."
            }
            say(p, pickThought(thoughts)); s.lastThought = nowR
        end
        return
    end
    local unh = readUnhappiness(p); if unh == nil then return end
    if unh < DP.threshold then
        if s.severeSince then log("Severe unhappiness timer reset; level fell below threshold.") end
        s.severeSince = nil; s.nextRollAt = nil; s.warningAt = nil; s.nextAmbientThought = nil
        return
    end
    if not s.severeSince then
        s.severeSince = nowH
        s.nextRollAt = nowH + DP.rollIntervalHours
        s.warningAt = nowR
        s.nextAmbientThought = nowR + DP.ambientThoughtIntervalSeconds
        say(p, pickThought({
            "I haven't felt right for a while...",
            "I don't know how much longer I can keep this up...",
            "Everything's been getting to me lately...",
            "I feel worn down... and it's not getting better."
        }))
        log(string.format("Severe unhappiness timer started at %.1f/100. First chance roll in 10 in-game minutes.", unh))
        return
    end
    local elapsed = nowH - s.severeSince
    if not s.nextRollAt then s.nextRollAt = nowH + DP.rollIntervalHours end
    if not s.nextAmbientThought then s.nextAmbientThought = nowR + DP.ambientThoughtIntervalSeconds end
    local thoughtInterval = DP.ambientThoughtIntervalSeconds
    if elapsed >= DP.escalationHours * 0.75 then thoughtInterval = 15 end
    if nowR >= s.nextAmbientThought then
        local thoughts = {
            "I don't know how much longer I can do this...",
            "I'm so tired of everything...",
            "I just want things to get better.",
            "I can't keep pretending I'm okay.",
            "Why does everything feel so hard?",
            "I need a break from all of this...",
            "I wish I could just feel normal again...",
            "I'm trying... I'm really trying.",
            "I feel completely drained...",
            "Nothing feels easy anymore...",
            "I just want one quiet moment...",
            "I don't feel like myself lately..."
        }
        say(p, pickThought(thoughts))
        s.nextAmbientThought = nowR + thoughtInterval
        log(string.format("Ambient depression thought shown; %.2f in-game hours into current cycle.", elapsed))
    end

    -- At 100 unhappiness, guarantee one episode per continuous qualifying hour if no earlier roll triggered.
    -- At lower values, make one independent chance roll every 10 in-game minutes.
    if nowH >= s.nextRollAt then
        local chance = breakdownChance(unh)
        if unh >= 100 and elapsed < DP.escalationHours then
            -- Keep the one-hour guarantee, but continue the countdown without repeated 100% rolls.
            s.nextRollAt = s.severeSince + DP.escalationHours
            log(string.format("Unhappiness 100/100: guaranteed breakdown scheduled at the one-hour mark (%.2f hours elapsed).", elapsed))
        else
            local roll = 100
            local okRoll, value = pcall(function() return ZombRand(10000) end)
            if okRoll and type(value) == "number" then roll = value / 100
            else roll = math.random(0, 9999) / 100 end
            log(string.format("BREAKDOWN CHANCE ROLL: unhappiness=%.1f/100; chance=%.1f%%; roll=%.2f%%; elapsed=%.2f in-game hours.", unh, chance, roll, elapsed))
            if roll < chance or (unh >= 100 and elapsed >= DP.escalationHours) then
                startEpisode(p, s, nowR, unh, chance, roll)
                return
            end
            s.nextRollAt = nowH + DP.rollIntervalHours
        end
    end
end

Events.OnPlayerUpdate.Add(HumanLimits.onDepressionPlayerUpdate)
log(string.format("Depression breakdown v%s loaded. Threshold %.0f/100; rolls every %.0f in-game minutes; chance curve 70:5%%, 75:10%%, 80:20%%, 85:35%%, 90:50%%, 95:75%%, 100:guaranteed after 1 continuous hour; episode %.0f real seconds.", DP.version, DP.threshold, DP.rollIntervalHours * 60, DP.episodeSeconds))
