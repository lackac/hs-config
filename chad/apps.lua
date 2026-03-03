local cache = { choices = {}, choiceList = {} }
local module = {
  useFzf = true,
  cache = cache,
}

local log

local home = os.getenv("HOME")
local searchPaths = {
  "/Applications/Nix Apps",
  home .. "/Applications/Home Manager Apps",
}

hs.fnutils.concat(searchPaths, {
  "/Applications",
  "/Applications/Setapp",
  "/System/Applications",
  "/System/Applications/Utilities",
  home .. "/Applications",
  "/System/Library/PreferencePanes",
  "/Library/PreferencePanes",
  home .. "/Library/PreferencePanes",
  "/System/Library/CoreServices",
  "/System/Library/CoreServices/Applications",
})

local function load(key)
  return hs.settings.get(module.requireName .. ":" .. key) or {}
end

local function save(key, value)
  return hs.settings.set(module.requireName .. ":" .. key, value)
end

local function generateChoice(appInfo)
  return {
    text = appInfo.name,
    subText = appInfo.path,
    id = appInfo.path,
    source = module.requireName,
    image = hs.image.iconForFile(appInfo.path),
  }
end

local function loadApplications()
  local modTimes = load("modTimes")
  local appsByPath = load("appsByPath")
  local changed = false
  local searchPathsMap = {}

  for _, path in ipairs(searchPaths) do
    searchPathsMap[path] = true
  end

  for path, _ in pairs(modTimes) do
    if not searchPathsMap[path] then
      changed = true
      modTimes[path] = nil
    end
  end

  for path, _ in pairs(appsByPath) do
    if not searchPathsMap[path] then
      changed = true
      appsByPath[path] = nil
      cache.choices[path] = nil
    end
  end

  for _, path in ipairs(searchPaths) do
    local mode = hs.fs.attributes(path, "mode")
    if mode ~= "directory" then
      if modTimes[path] ~= nil or appsByPath[path] ~= nil or cache.choices[path] ~= nil then
        changed = true
        modTimes[path] = nil
        appsByPath[path] = nil
        cache.choices[path] = nil
      end
    else
      local modTime = modTimes[path]
      local currentModTime = hs.fs.attributes(path, "modification") or 0

      if modTime == nil or currentModTime > modTime then
        changed = true
        local appInfos = {}
        for app in hs.fs.dir(path) do
          local name, ext = string.match(app, "^(.*)%.(.*)$")
          if ext == "app" or ext == "prefPane" then
            local fullPath = path .. "/" .. app
            local appInfo = { name = name, path = fullPath }
            table.insert(appInfos, appInfo)
          end
        end

        table.sort(appInfos, function(a, b)
          local nameA = a.name:lower()
          local nameB = b.name:lower()
          if nameA == nameB then
            return a.path < b.path
          end
          return nameA < nameB
        end)

        appsByPath[path] = appInfos
        cache.choices[path] = {}
        for _, appInfo in ipairs(appInfos) do
          table.insert(cache.choices[path], generateChoice(appInfo))
        end
        modTimes[path] = currentModTime
      elseif cache.choices[path] == nil then
        cache.choices[path] = {}
        for _, appInfo in ipairs(appsByPath[path] or {}) do
          table.insert(cache.choices[path], generateChoice(appInfo))
        end
      end
    end
  end

  cache.choiceList = {}
  for _, path in ipairs(searchPaths) do
    if cache.choices[path] then
      for _, choice in ipairs(cache.choices[path]) do
        table.insert(cache.choiceList, choice)
      end
    end
  end

  if changed then
    save("modTimes", modTimes)
    save("appsByPath", appsByPath)
  end
end

module.compileChoices = function(query)
  log.v("compileChoices " .. hs.inspect(query))
  if query ~= "" then
    return cache.choiceList or {}
  else
    return {}
  end
end

module.complete = function(choice)
  log.v("complete choice: " .. hs.inspect(choice))
  hs.open(choice.subText)
end

module.start = function(main, _)
  module.main = main
  log = hs.logger.new(module.requireName, "debug")

  loadApplications()
end

module.stop = function() end

module.refreshApplications = function()
  save("modTimes", {})
  cache.choices = {}
  cache.choiceList = {}
  loadApplications()
end

return module
