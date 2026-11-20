-- VRR has one owner: the control-center panel / ~/.local/bin/vrrctl.
-- Loaded after shell overrides so old quick-toggle values cannot shadow it.
local path = os.getenv("HOME") .. "/.config/hypr/vrr-policies.lua"
local ok, settings = pcall(dofile, path)
hl.config({misc={vrr=ok and settings.global or 2}})
