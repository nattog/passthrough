-- example script for passthrough mod

-- first ensure that passthrough is active in SYSTEM > MODS > PASSTHROUGH
-- when requiring passthrough mod, ensure that the casing is correct
local mod = require 'core/mods'
local tab = require "tabutil"

-- only used in the scope of this example, not necessary to run passthrough
local utils = require 'passthrough/lib/utils'

-- runs a check to ensure that the mod is loaded
local mod_running = tab.contains(mod.loaded_mod_names(), 'passthrough')
local passthrough = mod_running and require 'passthrough/lib/mod' or nil

-- script-level callbacks for midi event
-- data is your midi, origin lets you know where it comes from
function user_midi_event(id, data)
    local msg = midi.to_msg(data)
    -- do something with your data
    if msg.type ~= 'clock' then
      utils.examples_start_screen_datum({type = msg.type, port = passthrough.get_port_from_id(id)})
    end
end

function init()
  if mod_running then
    -- optional
    -- this informs passthrough about the script-defined callbacks for midi data
    passthrough.user_event = user_midi_event
 
    -- all code onwards is purely decorative, example script specific
    utils.examples_screen_init()
    
    local screen_framerate = 15
    local screen_refresh_metro
    screen_refresh_metro = metro.init()
    screen_refresh_metro.event = function()
      redraw()
    end
    screen_refresh_metro:start(1 / screen_framerate)
    
  end
end

function redraw()
  utils.examples_draw()
end
