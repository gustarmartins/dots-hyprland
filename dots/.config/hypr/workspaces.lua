for group = 0, 2 do
    local offset = group * 10
    for workspace = 1, 5 do
        hl.workspace_rule({ workspace = tostring(offset + workspace), monitor = "DP-1" })
    end
    for workspace = 6, 10 do
        hl.workspace_rule({ workspace = tostring(offset + workspace), monitor = "HDMI-A-1" })
    end
end

hl.workspace_rule({ workspace = "31", monitor = "DP-1" })
