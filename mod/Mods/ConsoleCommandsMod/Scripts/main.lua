GlobalAr = nil

function Log(Message)
    print(Message .. "\n")
    if type(GlobalAr) == "userdata" and GlobalAr:type() == "FOutputDevice" then
        GlobalAr:Log(Message)
    end
end

-- One-armed robber: OARCommands' summon (counts, friendly names, loads first) replaces this one
-- require("summon_unloaded_assets")
require("set")
require("dump_object")