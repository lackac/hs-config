local script = "scripts/rex-app-metadata.lua"
local shell = { label = "Shell", window_id = "window:shell", focused_block_id = "block:shell" }
local first = { label = "Window 11111111", window_id = "window:11111111", focused_block_id = "block:first" }
local second = { label = "Window 22222222", window_id = "window:22222222", focused_block_id = "block:second" }

local function run(sample, views, hosts)
  local sessions = {}
  for id in pairs(views) do
    sessions[#sessions + 1] = { label = "same-project", session_id = id }
  end
  local mock = {
    args = sample,
    call = function(method, args)
      if method == "hosts.list" then
        return { hosts = hosts }
      elseif method == "session.list" then
        return { sessions = sessions }
      end
      assert(method == "com.superlogical.terminal.process")
      return { foreground = { cwd = "/" .. args.session_id .. "/" .. args.block_id } }
    end,
    session = {
      attach = function(args)
        return { view = views[args.session_id] }
      end,
    },
  }
  return assert(loadfile(script, "t", { rex = mock, ipairs = ipairs }))()
end

local one = { windows = { shell }, active_window_id = shell.window_id }
local two = { windows = { first, second }, active_window_id = first.window_id }
local sample = { session = "same-project", label = "zsh ~", count = 2, index = 1 }
local views = { original = two, duplicate = one }
assert(run(sample, views).cwd == "/original/block:first", "The tab count distinguishes the duplicate session")

two.active_window_id, sample.index = second.window_id, 2
assert(run(sample, views).cwd == "/original/block:second", "The selected index distinguishes identical titles")

sample.index = 1
assert(not run(sample, views), "A stale selected index must not match")
sample.index = 2
assert(not run(sample, { original = two, duplicate = two }), "An ambiguous session must not match")
assert(not run(sample, views, { "remote" }), "A window on an unknown host must not match")

sample.index, sample.count = 1, 1
assert(not run(sample, views), "A named tab with a different visible label must not match")
sample.label = "Shell"
assert(run(sample, views).cwd == "/duplicate/block:shell", "An explicitly named tab must match")

print("Rex app metadata: 7 checks passed")
