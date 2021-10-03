-- passthrough

-- when requiring passthrough, ensure that the casing is correct
local passthrough = require 'passthrough/lib/passthrough'

-- only used in the scope of this example, not necessary to run passthrough
local utils = require 'passthrough/lib/utils'

-- script-level callbacks for midi event
-- data is your midi, origin lets you know where it comes from
function user_midi_event(data, origin)
    local msg = midi.to_msg(data)
    if msg.type ~= 'clock' then
      -- do something with your data
      utils.examples_start_screen_datum({type = msg.type, port = origin.port})
    end
end

function init()
  -- passthrough lib must be initialised on script load
  passthrough.init()

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

function redraw()
  utils.examples_draw()
end
