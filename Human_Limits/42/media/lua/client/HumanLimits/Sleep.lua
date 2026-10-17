-- Human Limits v0.2.2: nicotine-withdrawal-scaled sleep interruption
-- 0.00 withdrawal = 0% chance; 0.51 withdrawal = 70% chance.
HumanLimits = HumanLimits or {}
HumanLimits.SmokerSleep = HumanLimits.SmokerSleep or {}
local SS = HumanLimits.SmokerSleep
SS.version = "0.2.2"
SS.maxWithdrawal = 0.51
SS.maxChancePercent = 70
SS.wakeDelayHours = 0.5 -- approximately 30 in-game minutes
SS.states = SS.states or {}
SS.warnedMissingWithdrawal = false

local function log(message)
    if HumanLimits.log then
        HumanLimits.log("[Sleep] " .. tostring(message))
    else
        print("[HumanLimits][Sleep] " .. tostring(message))
    end
end

local function worldHours()
    local ok, value = pcall(function()
        return getGameTime():getWorldAgeHours()
    end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function readWithdrawal(player)
    if not CharacterStat or CharacterStat.NICOTINE_WITHDRAWAL == nil then
        if not SS.warnedMissingWithdrawal then
            SS.warnedMissingWithdrawal = true
            log("WARNING: CharacterStat.NICOTINE_WITHDRAWAL unavailable; interruption disabled.")
        end
        return nil
    end
    local okStats, stats = pcall(function() return player:getStats() end)
    if not okStats or not stats then return nil end
    local okValue, value = pcall(function()
        return stats:get(CharacterStat.NICOTINE_WITHDRAWAL)
    end)
    if not okValue or type(value) ~= "number" then
        if not SS.warnedMissingWithdrawal then
            SS.warnedMissingWithdrawal = true
            log("WARNING: could not read nicotine withdrawal stat; interruption disabled.")
        end
        return nil
    end
    if value < 0 then value = 0 end
    if value > SS.maxWithdrawal then value = SS.maxWithdrawal end
    return value
end

local function interruptionChance(withdrawal)
    if not withdrawal or withdrawal <= 0 then return 0 end
    return math.min(SS.maxChancePercent, (withdrawal / SS.maxWithdrawal) * SS.maxChancePercent)
end

local function isAsleep(player)
    local ok, result = pcall(function() return player:isAsleep() end)
    return ok and result == true
end

local function wakePlayer(player)
    local ok, err = pcall(function() player:forceAwake() end)
    if not ok then log("ERROR: forceAwake failed: " .. tostring(err)) end
    return ok
end

local function say(player, message)
    local ok, err = pcall(function() player:Say(message) end)
    if not ok then log("Speech bubble failed: " .. tostring(err)) end
    log("Thought: " .. message)
end

function HumanLimits.onSmokerSleepPlayerUpdate(player)
    if not player then return end
    local localPlayer = getPlayer()
    if localPlayer and player ~= localPlayer then return end

    local okDead, dead = pcall(function() return player:isDead() end)
    if okDead and dead then
        SS.states[player] = nil
        return
    end

    local now = worldHours()
    if not now then return end
    local asleep = isAsleep(player)
    local state = SS.states[player]

    if not state then
        SS.states[player] = {
            wasAsleep = asleep,
            wakeAt = nil,
            pendingCravingThought = false
        }
        log("Tracking player sleep state; currently asleep=" .. tostring(asleep))
        return
    end

    -- Detect the beginning of a sleep attempt and roll once for that attempt.
    if asleep and not state.wasAsleep then
        state.wakeAt = nil
        local withdrawal = readWithdrawal(player)
        if withdrawal ~= nil then
            local chance = interruptionChance(withdrawal)
            local roll = 100
            local okRoll, value = pcall(function() return ZombRand(10000) end)
            if okRoll and type(value) == "number" then roll = value / 100 end
            if roll < chance then
                state.wakeAt = now + SS.wakeDelayHours
                log(string.format(
                    "Sleep interruption triggered: withdrawal=%.3f/%.2f; chance=%.1f%%; roll=%.2f%%; wake scheduled in %.1f in-game minutes.",
                    withdrawal, SS.maxWithdrawal, chance, roll, SS.wakeDelayHours * 60
                ))
            else
                log(string.format(
                    "Sleep interruption avoided: withdrawal=%.3f/%.2f; chance=%.1f%%; roll=%.2f%%.",
                    withdrawal, SS.maxWithdrawal, chance, roll
                ))
            end
        end

    -- While asleep, check whether the scheduled wake time has arrived.
    elseif asleep and state.wakeAt ~= nil and now >= state.wakeAt then
        state.wakeAt = nil
        state.pendingCravingThought = true
        log("Waking player due to nicotine-withdrawal sleep interruption.")
        wakePlayer(player)
        state.wasAsleep = asleep
        return

    -- When the player is awake again, show the thought if this module woke them.
    elseif not asleep and state.wasAsleep then
        state.wakeAt = nil
        if state.pendingCravingThought then
            say(player, "Fuck, I need a cigarette. I can't sleep without it.")
            state.pendingCravingThought = false
            log("Player woke from withdrawal-related sleep interruption; craving thought shown.")
        end
    end

    state.wasAsleep = asleep
end

Events.OnPlayerUpdate.Add(HumanLimits.onSmokerSleepPlayerUpdate)
log(string.format(
    "Nicotine-withdrawal sleep module v%s loaded. Chance scales 0%% at 0 withdrawal to %.0f%% at %.2f withdrawal; wake delay %.1f in-game minutes.",
    SS.version, SS.maxChancePercent, SS.maxWithdrawal, SS.wakeDelayHours * 60
))
