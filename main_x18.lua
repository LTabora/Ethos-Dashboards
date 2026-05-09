--[[
  HeliDash X18 - VBar-style telemetry dashboard for FrSky ETHOS
  Target: FrSky X18 / X18S, ETHOS 1.6.x

  Install:
    1) Create folder on radio SD: /scripts/helidash/
    2) Save this file as: /scripts/helidash/main.lua
    3) Restart Lua or reboot radio
    4) Add a full-screen widget and choose "HeliDash"
    5) Configure the widget and pick your telemetry sources

  Notes:
    - Model name is read from the active model when ETHOS exposes it to Lua.
    - Flight Time is read from the configured Timer 1 source first, with
      API fallbacks for radios that expose model.getTimer(0).
    - Used mAh comes from the configured consumed-capacity source if present;
      otherwise it is integrated from the configured current source.
--]]

local APP_NAME = "HeliDash X18"
local APP_KEY  = "HD18"
local VERSION  = "0.2.3-x18-frame"

local REFRESH_HZ = 2
local MAH_PER_AMP_SECOND = 1000 / 3600

local colors = nil

local lipoPercentCurve = {
  { 3.000,   0 },
  { 3.401,   4 },
  { 3.544,   6 },
  { 3.664,   9 },
  { 3.705,  14 },
  { 3.735,  20 },
  { 3.762,  25 },
  { 3.786,  30 },
  { 3.802,  35 },
  { 3.818,  40 },
  { 3.833,  44 },
  { 3.850,  49 },
  { 3.870,  55 },
  { 3.897,  60 },
  { 3.923,  65 },
  { 3.955,  70 },
  { 3.987,  75 },
  { 4.021,  80 },
  { 4.062,  85 },
  { 4.111,  90 },
  { 4.135,  95 },
  { 4.200, 100 },
}

local function clamp(v, lo, hi)
  if v == nil then return lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(v, decimals)
  if v == nil then return nil end
  local m = 10 ^ (decimals or 0)
  return math.floor(v * m + 0.5) / m
end

local function ensureColors()
  if colors ~= nil then return end

  colors = {
    black = nil,
    line = nil,
    title = nil,
    label = nil,
    value = nil,
    warning = nil,
    normal = nil,
  }

  if lcd and lcd.RGB then
    colors.black = lcd.RGB(0, 0, 0)
    colors.line = lcd.RGB(220, 230, 205)
    colors.title = lcd.RGB(235, 240, 220)
    colors.label = lcd.RGB(150, 175, 120)
    colors.value = lcd.RGB(255, 255, 245)
    colors.warning = lcd.RGB(255, 210, 120)
    colors.normal = lcd.RGB(255, 255, 255)
  end
end

local function setColor(color)
  if color == nil or lcd == nil then return end
  if lcd.color then
    pcall(function() lcd.color(color) end)
  end
end

local function resetColor()
  ensureColors()
  setColor(colors.normal)
end

local function sourceValue(src)
  if src == nil then return nil end

  local ok, val = pcall(function() return src:value() end)
  if ok and val ~= nil then return val end

  ok, val = pcall(function() return src.value(src) end)
  if ok and val ~= nil then return val end

  return nil
end

local function sourceString(src)
  if src == nil then return nil end

  local ok, val = pcall(function() return src:stringValue() end)
  if ok and val ~= nil and val ~= "" then return tostring(val) end

  ok, val = pcall(function() return src.stringValue(src) end)
  if ok and val ~= nil and val ~= "" then return tostring(val) end

  return nil
end

local function getSystemSource(names)
  if system == nil or system.getSource == nil then return nil end

  for i = 1, #names do
    local name = names[i]
    local ok, src = pcall(function() return system.getSource(name) end)
    if ok and src ~= nil then return src end

    ok, src = pcall(function() return system.getSource({ name = name }) end)
    if ok and src ~= nil then return src end
  end

  return nil
end

local function tableNameValue(tbl)
  if type(tbl) ~= "table" then return nil end

  local keys = {
    "name",
    "modelName",
    "currentModelName",
    "activeModelName",
    "filename",
  }

  for i = 1, #keys do
    local value = tbl[keys[i]]
    if type(value) == "string" and value ~= "" then
      return value
    end
  end

  return nil
end

local function formatNumber(v, decimals)
  if v == nil then return nil end
  if decimals ~= nil then v = round(v, decimals) end
  return tostring(v)
end

local function formatSeconds(seconds)
  seconds = tonumber(seconds) or 0
  if seconds < 0 then seconds = -seconds end

  local hours = math.floor(seconds / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  local secs = math.floor(seconds % 60)

  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, mins, secs)
  end

  return string.format("%02d:%02d", mins, secs)
end

local function lipoVoltagePercent(packVoltage, cellCount)
  if packVoltage == nil or cellCount == nil or cellCount <= 0 then return nil end

  local cellVoltage = packVoltage / cellCount

  if cellVoltage <= lipoPercentCurve[1][1] then return 0 end
  if cellVoltage >= lipoPercentCurve[#lipoPercentCurve][1] then return 100 end

  for i = 2, #lipoPercentCurve do
    local upper = lipoPercentCurve[i]
    if cellVoltage <= upper[1] then
      local lower = lipoPercentCurve[i - 1]
      local span = upper[1] - lower[1]
      if span <= 0 then return upper[2] end

      local ratio = (cellVoltage - lower[1]) / span
      return lower[2] + (upper[2] - lower[2]) * ratio
    end
  end

  return 0
end

local function getModelName(widget)
  if model then
    local nameFn = model.name
    if type(nameFn) == "function" then
      local ok, name = pcall(function() return nameFn() end)
      if ok and type(name) == "string" and name ~= "" then
        return name
      end

      ok, name = pcall(function() return nameFn(model) end)
      if ok and type(name) == "string" and name ~= "" then
        return name
      end
    elseif type(nameFn) == "string" and nameFn ~= "" then
      return nameFn
    end

    if model.getInfo then
      local ok, info = pcall(function() return model.getInfo() end)
      if ok and info and info.name and info.name ~= "" then
        return info.name
      end
    end

    local modelKeys = { "modelName", "getName", "getModelName" }
    for i = 1, #modelKeys do
      local value = model[modelKeys[i]]
      if type(value) == "string" and value ~= "" then
        return value
      end
      if type(value) == "function" then
        local ok, result = pcall(function() return value() end)
        if ok then
          if type(result) == "string" and result ~= "" then
            return result
          end
          local tableName = tableNameValue(result)
          if tableName ~= nil then return tableName end
        end

        ok, result = pcall(function() return value(model) end)
        if ok then
          if type(result) == "string" and result ~= "" then
            return result
          end
          local tableName = tableNameValue(result)
          if tableName ~= nil then return tableName end
        end
      end
    end
  end

  if system then
    local directKeys = {
      "modelName",
      "currentModelName",
      "activeModelName",
    }

    for i = 1, #directKeys do
      local value = system[directKeys[i]]
      if type(value) == "string" and value ~= "" then
        return value
      end
    end

    local getterNames = {
      "getModelName",
      "getCurrentModelName",
      "getActiveModelName",
      "getModel",
      "getCurrentModel",
      "getActiveModel",
      "model",
      "currentModel",
      "activeModel",
    }

    for i = 1, #getterNames do
      local getter = system[getterNames[i]]
      if getter ~= nil then
        local ok, info = pcall(function() return getter() end)
        if ok then
          if type(info) == "string" and info ~= "" then
            return info
          end
          local tableName = tableNameValue(info)
          if tableName ~= nil then return tableName end
        end
      end
    end

    if system.getVersion then
      local ok, info = pcall(function() return system.getVersion() end)
      if ok then
        local tableName = tableNameValue(info)
        if tableName ~= nil then return tableName end
      end
    end
  end

  local modelSource = getSystemSource({
    "Model Name",
    "Model name",
    "ModelName",
    "Current Model",
    "Current model",
    "Active Model",
    "Active model",
    "Model",
  })
  local modelText = sourceString(modelSource)
  if modelText ~= nil then return modelText end

  return widget.modelName ~= "" and widget.modelName or "Model"
end

local function getTimer1Text(widget)
  local timerSource = widget.srcTimer1 or getSystemSource({
    "Timer 1",
    "Timer1",
    "Tmr1",
    "Tmr 1",
    "T1",
  })

  local timerText = sourceString(timerSource)
  if timerText ~= nil then return timerText end

  local timerValue = sourceValue(timerSource)
  if timerValue ~= nil then return formatSeconds(timerValue) end

  if model and model.getTimer then
    local ok, timer = pcall(function() return model.getTimer(0) end)
    if ok and timer ~= nil then
      if type(timer) == "table" and timer.value ~= nil then
        return formatSeconds(timer.value)
      end
      if type(timer) == "number" then
        return formatSeconds(timer)
      end
    end
  end

  return formatSeconds(widget.flightSeconds or 0)
end

local function resetTimer1()
  if model and model.resetTimer then
    pcall(function() model.resetTimer(0) end)
  end
end

local function drawLine(x1, y1, x2, y2)
  ensureColors()
  setColor(colors.line)
  lcd.drawLine(x1, y1, x2, y2)
end

local function drawBox(x, y, w, h)
  ensureColors()
  setColor(colors.line)
  lcd.drawLine(x, y, x + w, y)
  lcd.drawLine(x, y, x, y + h)
  lcd.drawLine(x + w, y, x + w, y + h)
  lcd.drawLine(x, y + h, x + w, y + h)
end

local function drawMetric(x, y, label, value, unit, big, warn)
  ensureColors()

  setColor(colors.label)
  lcd.drawText(x, y, label, FONT_S)

  local text = value or "---"
  if unit and text ~= "---" then
    text = text .. " " .. unit
  end

  setColor(warn and colors.warning or colors.value)
  lcd.drawText(x, y + 14, text, FONT_M)

  setColor(colors.line)
  local cx = x - 8
  local cy = y + 21
  lcd.drawLine(cx - 4, cy, cx + 4, cy)
  lcd.drawLine(cx, cy - 4, cx, cy + 4)
end

local function create()
  return {
    modelName = "",
    packCapacity = 5000,
    cellCount = 6,
    minCellVoltage = 3.50,
    resetSwitch = nil,

    srcVoltage = nil,
    srcCurrent = nil,
    srcRpm = nil,
    srcEscTemp = nil,
    srcRxVoltage = nil,
    srcConsumed = nil,
    srcTimer1 = nil,

    maxCurrent = 0,
    maxPower = 0,
    minVoltage = nil,
    maxVoltage = nil,
    consumedMah = 0,
    remainingPct = 100,
    lastClock = nil,
    lastPaint = 0,
    flightSeconds = 0,
    lastResetActive = false,
  }
end

local function read(widget)
  widget.modelName      = storage.read("modelName") or ""
  widget.packCapacity   = storage.read("packCapacity") or 5000
  widget.cellCount      = storage.read("cellCount") or 6
  widget.minCellVoltage = storage.read("minCellVoltage") or 3.50

  widget.srcVoltage     = storage.read("srcVoltage")
  widget.srcCurrent     = storage.read("srcCurrent")
  widget.srcRpm         = storage.read("srcRpm")
  widget.srcEscTemp     = storage.read("srcEscTemp")
  widget.srcRxVoltage   = storage.read("srcRxVoltage")
  widget.srcConsumed    = storage.read("srcConsumed")
  widget.srcTimer1      = storage.read("srcTimer1")
  widget.resetSwitch    = storage.read("resetSwitch")
  return true
end

local function write(widget)
  storage.write("modelName", widget.modelName)
  storage.write("packCapacity", widget.packCapacity)
  storage.write("cellCount", widget.cellCount)
  storage.write("minCellVoltage", widget.minCellVoltage)

  storage.write("srcVoltage", widget.srcVoltage)
  storage.write("srcCurrent", widget.srcCurrent)
  storage.write("srcRpm", widget.srcRpm)
  storage.write("srcEscTemp", widget.srcEscTemp)
  storage.write("srcRxVoltage", widget.srcRxVoltage)
  storage.write("srcConsumed", widget.srcConsumed)
  storage.write("srcTimer1", widget.srcTimer1)
  storage.write("resetSwitch", widget.resetSwitch)
  return true
end

local function resetFlight(widget, includeTimer)
  widget.maxCurrent = 0
  widget.maxPower = 0
  widget.minVoltage = nil
  widget.maxVoltage = nil
  widget.consumedMah = 0
  widget.remainingPct = 100
  widget.flightSeconds = 0
  widget.lastClock = os.clock()

  if includeTimer then
    resetTimer1()
  end
end

local function configure(widget)
  form.clear()

  local line

  line = form.addLine("Model name fallback")
  form.addTextField(line, nil,
    function() return widget.modelName end,
    function(value) widget.modelName = value end)

  line = form.addLine("Pack capacity mAh")
  form.addNumberField(line, nil, 500, 20000,
    function() return widget.packCapacity end,
    function(value) widget.packCapacity = value end)

  line = form.addLine("Cell count")
  form.addNumberField(line, nil, 1, 14,
    function() return widget.cellCount end,
    function(value) widget.cellCount = value end)

  line = form.addLine("Empty cell voltage x100")
  form.addNumberField(line, nil, 300, 420,
    function() return math.floor(widget.minCellVoltage * 100) end,
    function(value) widget.minCellVoltage = value / 100 end)

  line = form.addLine("Pack voltage source")
  form.addSourceField(line, nil,
    function() return widget.srcVoltage end,
    function(value) widget.srcVoltage = value end)

  line = form.addLine("Pack current source")
  form.addSourceField(line, nil,
    function() return widget.srcCurrent end,
    function(value) widget.srcCurrent = value end)

  line = form.addLine("Used capacity source")
  form.addSourceField(line, nil,
    function() return widget.srcConsumed end,
    function(value) widget.srcConsumed = value end)

  line = form.addLine("Timer 1 source")
  form.addSourceField(line, nil,
    function() return widget.srcTimer1 end,
    function(value) widget.srcTimer1 = value end)

  line = form.addLine("Motor RPM source")
  form.addSourceField(line, nil,
    function() return widget.srcRpm end,
    function(value) widget.srcRpm = value end)

  line = form.addLine("ESC temp source")
  form.addSourceField(line, nil,
    function() return widget.srcEscTemp end,
    function(value) widget.srcEscTemp = value end)

  line = form.addLine("RX voltage source")
  form.addSourceField(line, nil,
    function() return widget.srcRxVoltage end,
    function(value) widget.srcRxVoltage = value end)

  line = form.addLine("Reset switch/source")
  form.addSourceField(line, nil,
    function() return widget.resetSwitch end,
    function(value) widget.resetSwitch = value end)
end

local function menu(widget)
  return {
    { "Reset flight values", function()
      resetFlight(widget, true)
      if lcd.invalidate then lcd.invalidate() end
    end },
  }
end

local function wakeup(widget)
  local now = os.clock()
  if widget.lastClock == nil then widget.lastClock = now end

  local dt = now - widget.lastClock
  widget.lastClock = now

  local voltage = sourceValue(widget.srcVoltage)
  local current = sourceValue(widget.srcCurrent)
  local consumedSource = sourceValue(widget.srcConsumed)
  local resetVal = sourceValue(widget.resetSwitch)
  local resetActive = resetVal ~= nil and resetVal > 0

  if resetActive and not widget.lastResetActive then
    resetFlight(widget, true)
  end
  widget.lastResetActive = resetActive

  if current ~= nil then
    widget.maxCurrent = math.max(widget.maxCurrent or 0, current)

    if current > 2 and consumedSource == nil then
      widget.flightSeconds = widget.flightSeconds + dt
      widget.consumedMah = widget.consumedMah + current * dt * MAH_PER_AMP_SECOND
    end
  end

  if consumedSource ~= nil then
    widget.consumedMah = consumedSource
  end

  if voltage ~= nil then
    if widget.minVoltage == nil then widget.minVoltage = voltage end
    if widget.maxVoltage == nil then widget.maxVoltage = voltage end

    widget.minVoltage = math.min(widget.minVoltage, voltage)
    widget.maxVoltage = math.max(widget.maxVoltage, voltage)

    if current ~= nil then
      widget.maxPower = math.max(widget.maxPower or 0, voltage * current)
    end
  end

  if widget.packCapacity and widget.packCapacity > 0 then
    widget.remainingPct = clamp(100 - (widget.consumedMah / widget.packCapacity * 100), 0, 100)
  end

  if now - widget.lastPaint > (1 / REFRESH_HZ) then
    widget.lastPaint = now
    if lcd.invalidate then lcd.invalidate() end
  end
end

local function paint(widget)
  ensureColors()

  local rawW, rawH = lcd.getWindowSize and lcd.getWindowSize() or 480, 320

  if colors.black ~= nil then
    if lcd.clear then
      pcall(function() lcd.clear(colors.black) end)
    elseif lcd.drawFilledRectangle then
      setColor(colors.black)
      lcd.drawFilledRectangle(0, 0, rawW, rawH)
    end
  end

  local W = math.min(rawW, 480)

  local voltage = sourceValue(widget.srcVoltage)
  local current = sourceValue(widget.srcCurrent)
  local rpm = sourceValue(widget.srcRpm)
  local escTemp = sourceValue(widget.srcEscTemp)
  local rxV = sourceValue(widget.srcRxVoltage)
  local voltagePct = lipoVoltagePercent(voltage, widget.cellCount)

  local title = getModelName(widget)
  local used = round(widget.consumedMah or 0, 0)
  local remaining = round(widget.remainingPct or 0, 1)
  local emptyV = round(widget.cellCount * widget.minCellVoltage, 1)
  local fullV = widget.maxVoltage and round(widget.maxVoltage, 1) or nil
  local minV = widget.minVoltage and round(widget.minVoltage, 1) or nil
  local maxCur = round(widget.maxCurrent or 0, 1)
  local maxPower = round(widget.maxPower or 0, 1)
  local timer1 = getTimer1Text(widget)

  local borderW = W - 24
  local borderH = 220
  local borderX = math.floor((W - borderW) / 2)
  local borderY = 34

  drawBox(borderX, borderY, borderW, borderH)

  local col1 = borderX + 24
  local col2 = borderX + 170
  local col3 = borderX + 318

  local y = borderY + 7
  local rowH = 40

  drawMetric(col1, y, "Date / Time", os.date("%m.%d.%Y %H:%M"), nil, false)
  drawMetric(col2, y, "Model", title, nil, false)
  drawMetric(col3, y, "Remaining", formatNumber(remaining, 1), "%", true, remaining <= 25)

  y = y + rowH
  drawMetric(col1, y, "Capacity", tostring(widget.packCapacity), "mAh", true)
  drawMetric(col2, y, "Used", tostring(used), "mAh", true)
  drawMetric(col3, y, "Empty V", formatNumber(emptyV, 1), "V", true)

  y = y + rowH
  drawMetric(col1, y, "Full V", formatNumber(fullV, 1), "V", true)
  drawMetric(col2, y, "Min V", formatNumber(minV, 1), "V", true)
  drawMetric(col3, y, "Flight", timer1, nil, true)

  y = y + rowH
  drawMetric(col1, y, "Max A", formatNumber(maxCur, 1), "A", true)
  drawMetric(col2, y, "Max W", formatNumber(maxPower, 1), "W", true)
  drawMetric(col3, y, "RPM", formatNumber(rpm, 0), "rpm", false)

  y = y + rowH
  drawMetric(col1, y, "ESC Temp", formatNumber(escTemp, 0), "C", false)
  drawMetric(col2, y, "Volt %", formatNumber(voltagePct, 1), "%", false, voltagePct ~= nil and voltagePct <= 70)
  drawMetric(col3, y, "RX V", formatNumber(rxV, 1), "V", false)

  resetColor()
end

local function event(widget, category, value, x, y)
  return false
end

local function init()
  system.registerWidget({
    key = APP_KEY,
    name = APP_NAME,
    create = create,
    read = read,
    write = write,
    configure = configure,
    menu = menu,
    wakeup = wakeup,
    paint = paint,
    event = event,
    persistent = false,
  })
end

return { init = init }
