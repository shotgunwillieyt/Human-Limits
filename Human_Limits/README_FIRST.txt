Human Limits v0.2.9 — Recurring Depression Breakdown Test Build (Build 42.21)

INSTALL
1. Close Project Zomboid.
2. Back up the existing Human_Limits folder, then replace it with this folder.
3. Confirm paths are Human_Limits/42/mod.info and Human_Limits/42/media/...
4. Check console.txt for Human Limits v0.2.9 load messages.

PRESERVED BASELINE
- Panic heart-attack system (same gameplay logic).
- Nicotine-withdrawal-scaled sleep interruption and wake thought.
- Repeatable fatigue blackout system.
- Depression breakdown movement lock, item-drop attempt, messages, and 10 real-second duration.

DEPRESSION TEST
- Uses only vanilla unhappiness; no separate depression mod or trait check.
- Threshold: unhappiness >= 70/100.
- First breakdown after one continuous in-game hour above threshold.
- After each episode ends, the one-hour timer resets. If unhappiness remains >=70, another breakdown occurs after the next qualifying hour.
- If unhappiness falls below 70, the current countdown resets.
- Random natural thoughts appear between episodes, more frequently during the final quarter of the countdown.
- Episode duration remains 10 real-world seconds.

TESTING
The recurring timer and ambient thoughts need in-game confirmation. Check console.txt for [HumanLimits][Depression] messages. Crouching is best-effort and was not confirmed to work; movement lock and 10-second duration were confirmed in the previous build.
