local cache = { task = nil, queue = nil }
local module = { cache = cache }
local log = hs.logger.new("keyboard", "debug")

local APPLY_COMMANDS = {
  {
    name = "all keyboards",
    matching = '{"PrimaryUsagePage":1,"PrimaryUsage":6}',
    payload = table.concat({
      '{"UserKeyMapping":[',
      '{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000e0},',
      '{"HIDKeyboardModifierMappingSrc":0x7000000e0,"HIDKeyboardModifierMappingDst":0x70000006e}',
      "]}",
    }),
  },
  {
    name = "internal keyboard",
    matching = '{"ProductID":0x0,"VendorID":0x0,"PrimaryUsagePage":1,"PrimaryUsage":6}',
    payload = table.concat({
      '{"UserKeyMapping":[',
      '{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000e0},',
      '{"HIDKeyboardModifierMappingSrc":0x7000000e0,"HIDKeyboardModifierMappingDst":0x70000006e},',
      '{"HIDKeyboardModifierMappingSrc":0x700000064,"HIDKeyboardModifierMappingDst":0x700000035},',
      '{"HIDKeyboardModifierMappingSrc":0x700000035,"HIDKeyboardModifierMappingDst":0x700000064}',
      "]}",
    }),
  },
  {
    name = "voyager reset",
    matching = '{"ProductID":0x1977,"VendorID":0x3297}',
    payload = '{"UserKeyMapping":[]}',
  },
  {
    name = "splitkb reset",
    matching = '{"ProductID":0x3a07,"VendorID":0x8d1d}',
    payload = '{"UserKeyMapping":[]}',
  },
}

local RESET_COMMANDS = {
  {
    name = "all keyboards reset",
    matching = '{"PrimaryUsagePage":1,"PrimaryUsage":6}',
    payload = '{"UserKeyMapping":[]}',
  },
  {
    name = "internal keyboard reset",
    matching = '{"ProductID":0x0,"VendorID":0x0,"PrimaryUsagePage":1,"PrimaryUsage":6}',
    payload = '{"UserKeyMapping":[]}',
  },
  {
    name = "voyager reset",
    matching = '{"ProductID":0x1977,"VendorID":0x3297}',
    payload = '{"UserKeyMapping":[]}',
  },
  {
    name = "splitkb reset",
    matching = '{"ProductID":0x3a07,"VendorID":0x8d1d}',
    payload = '{"UserKeyMapping":[]}',
  },
}

local runSequence
local queueSequence

local drainQueue = function()
  if not cache.queue then
    return
  end

  ---@type {commands: table, name: string}|nil
  local queued = cache.queue

  if not queued then
    return
  end

  cache.queue = nil
  log.i("running queued hidutil update: " .. queued.name)
  queueSequence(queued.commands, queued.name)
end

queueSequence = function(commands, name)
  if cache.task then
    cache.queue = { commands = commands, name = name }
    log.w("hidutil update already running, queued " .. name)
    return false
  end

  runSequence(commands, name, 1)
  return true
end

runSequence = function(commands, name, index)
  local command = commands[index]

  if not command then
    log.i(name .. " complete")
    cache.task = nil
    drainQueue()

    return
  end

  log.df("Running hidutil command %d/%d for %s: %s", index, #commands, name, command.name)

  local task = hs.task.new("/usr/bin/hidutil", function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      log.ef(
        "hidutil failed for %s (%d): %s%s",
        command.name,
        exitCode,
        stdOut or "",
        stdErr or ""
      )
      cache.task = nil
      drainQueue()
      return
    end

    if stdErr and #stdErr > 0 then
      log.wf("hidutil stderr for %s: %s", command.name, stdErr)
    end

    if stdOut and #stdOut > 0 then
      log.df("hidutil output for %s: %s", command.name, stdOut)
    end

    runSequence(commands, name, index + 1)
  end, {
    "property",
    "--matching",
    command.matching,
    "--set",
    command.payload,
  })

  if not task then
    log.ef("failed to create hidutil task for %s", command.name)
    drainQueue()
    return
  end

  cache.task = task

  if not task:start() then
    log.ef("failed to start hidutil task for %s", command.name)
    cache.task = nil
    drainQueue()
  end
end

module.apply = function()
  return queueSequence(APPLY_COMMANDS, "keyboard remap apply")
end

module.reset = function()
  return queueSequence(RESET_COMMANDS, "keyboard remap reset")
end

module.start = function()
  module.apply()
end

module.stop = function() end

return module
