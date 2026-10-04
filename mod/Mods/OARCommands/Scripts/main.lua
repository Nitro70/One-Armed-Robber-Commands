--[[
    OARCommands for One-armed robber (UE4SS 3.0.1 Lua mod): the loader.

    Every command this mod adds lives in  Mods\OARCommands\config.lua : its values at the top,
    then the full code of each command. Edit that file, then type  reloadconfig  in the game's
    console to load it again without restarting the game.

        reloadconfig            load config.lua again
        reloadconfig default    load config.default.lua, the untouched copy the installer put next
                                to it (your config.lua is not changed)

    This file only does what cannot be done twice in one game session. UE4SS cannot take a
    console command, a key or a hook back once it is registered, so each one is registered here
    once, with a small function that looks up the current code from config.lua every time it
    runs. That is what makes reloading safe: nothing is ever registered a second time.

    If config.lua has an error, the error and its line number are printed in the console and in
    UE4SS.log. After a failed reloadconfig the commands that were loaded before keep working.
--]]

local MOD = "[OARCommands] "

local function ScriptDir()
    local src = debug.getinfo(1, "S").source
    return (src:gsub("^@", ""):match("^(.*)[/\\][^/\\]*$")) or "."
end

local SCRIPTS = ScriptDir()
local MOD_DIR = SCRIPTS .. "/.."
local CONFIG = MOD_DIR .. "/config.lua"
local DEFAULT_CONFIG = MOD_DIR .. "/config.default.lua"

local function Print(text)
    print(MOD .. text .. "\n")
end

-- Print to the UE4SS log and, when the command came from the console, into the console too.
local function Say(Ar, text)
    Print(text)
    if Ar then pcall(function() Ar:Log(text) end) end
end

-- What config.lua registered on its last successful load.
local function Empty()
    return { commands = {}, intercepts = {}, hooks = {}, newObjects = {}, keys = {} }
end
local Active = Empty()

-- What UE4SS has been told about (once each, for the whole game session).
local Registered = { names = {}, hooks = {}, classes = {}, keys = {} }
local Builtin = {}                    -- commands of this file (reloadconfig)

local Core = {
    ModDir = MOD_DIR,
    ScriptsDir = SCRIPTS,
    ConfigFile = CONFIG,
    State = {},                       -- kept across reloadconfig (not across a game restart)
    Exports = {},                     -- whatever config.lua wants other scripts to see
    Print = Print,
    Say = Say,
}
OARCommands = Core                    -- global, so other mods and the UE4SS console can reach it

local function Dispatcher(name)
    return function(FullCommand, Parameters, Ar)
        local own = Builtin[name] or Active.commands[name]
        local fn = own or Active.intercepts[name]
        if not fn then return false end                       -- not ours (any more): the engine gets it
        local ok, result = pcall(fn, FullCommand, Parameters or {}, Ar)
        if not ok then
            Say(Ar, name .. " failed: " .. tostring(result))
            return true
        end
        if own then return result ~= false end                -- a command of the mod: handled
        return result == true                                 -- an intercept: handled only when it says so
    end
end

local function EnsureDispatcher(name)
    if Registered.names[name] then return end
    Registered.names[name] = true
    RegisterConsoleCommandHandler(name, Dispatcher(name))
end

-- A console command of the mod. fn(FullCommand, Parameters, Ar); binds can call it directly.
-- Command names match exactly as typed, so register the spelling people will type (lowercase).
function Core.Command(name, fn)
    Active.commands[name] = fn
    EnsureDispatcher(name)
end

-- Look at an engine command before the engine does. fn returns true when it handled the command
-- and false to let the engine run it as usual.
function Core.Intercept(name, fn)
    Active.intercepts[name] = fn
    EnsureDispatcher(name)
end

-- The current code of one of the mod's commands (or nil), for binds.
function Core.OwnCommand(name)
    return Builtin[name] or Active.commands[name]
end

-- Whether the console would hand `name` to the mod right now (a command or an intercept).
function Core.Handles(name)
    return (Builtin[name] or Active.commands[name] or Active.intercepts[name]) ~= nil
end

-- Run fn every time the game calls the function at path ("/Script/Engine.PlayerController:ClientMessage").
-- Returns true when the hook is in place; false (and the reason) when the function does not exist
-- yet, for example a Blueprint that is not loaded. Call it again later in that case.
function Core.Hook(path, fn)
    Active.hooks[path] = fn
    if Registered.hooks[path] then return true end
    local ok, err = pcall(function()
        RegisterHook(path, function(...)
            local current = Active.hooks[path]
            if current then
                local ran, problem = pcall(current, ...)
                if not ran then Print("hook " .. path .. " failed: " .. tostring(problem)) end
            end
        end)
    end)
    Registered.hooks[path] = ok or nil
    return ok, err
end

-- Run fn(object) for every new object of a class ("/Script/Engine.DebugCameraController").
function Core.OnNewObject(class, fn)
    Active.newObjects[class] = fn
    if Registered.classes[class] then return end
    Registered.classes[class] = true
    NotifyOnNewObject(class, function(object)
        local current = Active.newObjects[class]
        if current then
            local ran, problem = pcall(current, object)
            if not ran then Print("new object watcher for " .. class .. " failed: " .. tostring(problem)) end
        end
    end)
end

-- Run fn when a key is pressed. keyName is a UE4SS key name (Key.X is "X").
-- Returns true when another UE4SS mod already watches that key.
function Core.KeyBind(keyName, fn)
    Active.keys[keyName] = fn
    if Registered.keys[keyName] then return false end
    Registered.keys[keyName] = true
    local shared = IsKeyBindRegistered(Key[keyName])
    RegisterKeyBind(Key[keyName], function()
        local current = Active.keys[keyName]
        if current then current() end
    end)
    return shared
end

-- A data table from the Scripts folder (spawnables, unlockables, maps), read again on every
-- reloadconfig, so edits to those files load too.
function Core.Data(name)
    return dofile(SCRIPTS .. "/" .. name .. ".lua")
end

-- Run a config file. On any error the commands that were loaded before stay as they were.
local function LoadConfig(path)
    local chunk, err = loadfile(path)
    if not chunk then return false, err end
    local before, exportsBefore = Active, Core.Exports
    Active, Core.Exports = Empty(), {}
    local ok, problem = pcall(chunk, Core)
    if not ok then
        Active, Core.Exports = before, exportsBefore
        return false, problem
    end
    Core.LoadedFrom = path
    local count = 0
    for _ in pairs(Active.commands) do count = count + 1 end
    return true, count
end

Builtin.reloadconfig = function(FullCommand, Parameters, Ar)
    local which = Parameters[1] and string.lower(Parameters[1]) or nil
    if which ~= nil and which ~= "default" then
        Say(Ar, "Usage: reloadconfig   or   reloadconfig default")
        return true
    end
    local path = which == "default" and DEFAULT_CONFIG or CONFIG
    local name = which == "default" and "config.default.lua" or "config.lua"
    local ok, result = LoadConfig(path)
    if ok then
        Say(Ar, string.format("Loaded %s: %d commands", name, result))
    else
        Say(Ar, name .. " was NOT loaded, the commands from before stay as they were. The error:")
        Say(Ar, tostring(result))
    end
    return true
end
EnsureDispatcher("reloadconfig")

local ok, result = LoadConfig(CONFIG)
if ok then
    Print(string.format("loaded %d commands from %s", result, CONFIG))
else
    Print("config.lua could not be loaded, so only reloadconfig works for now. The error:")
    Print(tostring(result))
    Print("Fix the file and type reloadconfig, or type  reloadconfig default  for the untouched copy.")
end
