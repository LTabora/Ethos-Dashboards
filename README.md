# HeliDash

HeliDash is a VBar-style telemetry dashboard widget for FrSky ETHOS radios. It was built for helicopter telemetry, with a dense field layout showing battery, voltage, current, power, RPM, ESC temperature, receiver voltage, model name, and Timer 1 flight time.

## Files

- `main.lua` - X20 / X20S / X20 Pro layout.
- `main_x18.lua` - X18 / X18S 480x320 layout.

## Current Versions

- X20 version: `0.1.6`
- X18 version: `0.2.3-x18-frame`

## Installation

### X20 / X20S / X20 Pro

1. Create this folder on the radio SD card:

   ```text
   /scripts/helidash/
   ```

2. Copy `main.lua` into that folder:

   ```text
   /scripts/helidash/main.lua
   ```

3. Restart Lua or reboot the radio.
4. Add a full-screen widget.
5. Select `HeliDash`.
6. Configure the widget telemetry sources.

### X18 / X18S

1. Create this folder on the radio SD card:

   ```text
   /scripts/helidash_x18/
   ```

2. Copy `main_x18.lua` into that folder and rename it to `main.lua`:

   ```text
   /scripts/helidash_x18/main.lua
   ```

3. Restart Lua or reboot the radio.
4. Add a full-screen widget.
5. Select `HeliDash X18`.
6. Configure the widget telemetry sources.

## Widget Configuration

Set these fields from the widget configuration menu:

- `Model name fallback` - optional fallback name if ETHOS does not expose the active model name to Lua.
- `Pack capacity mAh` - battery capacity used for remaining capacity calculation.
- `Cell count` - number of LiPo cells in the flight pack.
- `Empty cell voltage x100` - per-cell empty voltage multiplied by 100.
- `Pack voltage source` - main flight pack voltage telemetry source.
- `Pack current source` - current telemetry source.
- `Used capacity source` - consumed mAh telemetry source, if available.
- `Timer 1 source` - Timer 1 source for flight time.
- `Motor RPM source` - rotor or motor RPM telemetry source.
- `ESC temp source` - ESC temperature telemetry source.
- `RX voltage source` - receiver voltage telemetry source.
- `Reset switch/source` - optional switch/source used to reset flight values.

## Empty Cell Voltage

`Empty cell voltage x100` is the empty voltage per cell multiplied by 100.

Examples:

```text
350 = 3.50V per cell
360 = 3.60V per cell
370 = 3.70V per cell
```

For a 6S pack with `350` configured:

```text
3.50V x 6 cells = 21.0V empty pack voltage
```

## Battery Percentage

The `Volt %` / `Voltage Percent` field uses a LiPo voltage curve rather than a simple voltage ratio. This better matches the expected LiPo state-of-charge behavior.

For example, a 6S pack at `23.0V` is about `3.83V` per cell, which maps to roughly the mid-40% range on the LiPo curve.

## Reset Switch / Source

The reset source is intended to be a switch-like source that returns `0` when inactive and greater than `0` when active.

When triggered, it resets:

- Used capacity
- Remaining percentage
- Max current
- Max power
- Full voltage
- Min voltage
- Internal fallback flight timer
- Timer 1, if ETHOS allows `model.resetTimer(0)`

## Notes

- Model name is retrieved automatically from ETHOS using the same style as Zavionix widgets, with fallback paths for other Lua environments.
- Flight time should be assigned to `Timer 1 source` for best reliability.
- Used capacity comes from the configured consumed mAh source when available. If no consumed capacity source is configured, HeliDash estimates mAh by integrating current over time.
- Sensor names vary by receiver, ESC, FBL, and telemetry protocol. Use the widget source picker instead of hardcoding source names.

## Development

Run a local Lua syntax check with:

```powershell
lua -e "assert(loadfile('main.lua')); print('x20 syntax ok')"
lua -e "assert(loadfile('main_x18.lua')); print('x18 syntax ok')"
```

## Git

Typical update workflow:

```powershell
git status
git add main.lua main_x18.lua README.md
git commit -m "Update HeliDash dashboard scripts"
git push
```
