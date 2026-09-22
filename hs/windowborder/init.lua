local modulePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local nativePath = modulePath .. "../?.so"

if not package.cpath:find(nativePath, 1, true) then
  package.cpath = nativePath .. ";" .. package.cpath
end

return require("hs.libwindowborder")
