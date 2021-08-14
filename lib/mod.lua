local mod = require 'core/mods'


local state = {
  midi_device = 1,
  device_channel=1,
  midi_interface = 2,
  interface_channel=1,
  clock_device = 1,
  quantize_midi = 1,
  current_scale = 1,
  cc_direction = 1,
  root_note = 0
}

mod.hook.register("system_post_startup", "read passthrough state", function()
  local f = io.open(_path.data..'passthrough.state')
  if f ~= nil then
    io.close(f)
    state = dofile(_path.data..'passthrough.state')
    
  end
end)

mod.hook.register("system_pre_shutdown", "write passthrough state", function()
  local f = io.open(_path.data..'passthrough.state',"w+")
  io.output(f)
  io.write("return { midi_device="..state.midi_device..',')
  io.write("device_channel="..state.device_channel..',')
  io.write("midi_interface="..state.midi_interface..',')
  io.write("interface_channel="..state.interface_channel..',')
  io.write("clock_device="..state.clock_device..',')
  io.write("quantize_midi="..state.quantize_midi..',')
  io.write("current_scale="..state.current_scale..",")
  io.write("cc_direction="..state.cc_direction..",")
  io.write("root_note="..state.root_note.." }\n")
  io.close(f)
end)



local pt_core = require("passthrough/lib/core")
local Passthrough = {}
tab = require "tabutil"

local first_init = false
local devices = {}
local midi_device
local midi_interface
local clock_device
local quantize_midi
local current_scale = {}

local passthrough_config = {}


function Passthrough.user_device_event(data)
  print('user-device-event')
end

function Passthrough.user_interface_event(data)
  print('user-interface-event')
end


function Passthrough.device_event(data)
    pt_core.device_event(midi_interface, state.device_channel, state.interface_channel, state.quantize_midi, current_scale, data)
    Passthrough.user_device_event(data)
end

function Passthrough.interface_event(data)
    pt_core.interface_event(midi_device, state.device_channel, state.clock_device, state.cc_direction, data)
    Passthrough.user_interface_event(data)
end

function Passthrough.init()
    -- params:add_group("PASSTHROUGH", 9)
    -- params:add {
    --     type = "option",
    --     id = "midi_device",
    --     name = "Device",
    --     options = devices,
    --     default = 1,
    --     action = function(value)
    --         midi_device.event = nil
    --         midi_device = midi.connect(value)
    --         midi_device.event = Passthrough.device_event
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "midi_interface",
    --     name = "Interface",
    --     options = devices,
    --     default = 2,
    --     action = function(value)
    --         midi_interface.event = nil
    --         midi_interface = midi.connect(value)
    --         midi_interface.event = Passthrough.interface_event
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "cc_direction",
    --     name = "CC msg direction",
    --     options = cc_directions,
    --     default = 1
    -- }

    -- local channels = {"No change"}
    -- for i = 1, 16 do
    --     table.insert(channels, i)
    -- end
    -- params:add {
    --     type = "option",
    --     id = "device_channel",
    --     name = "Device channel",
    --     options = channels,
    --     default = 1
    -- }

    -- channels[1] = "Device src."
    -- params:add {
    --     type = "option",
    --     id = "interface_channel",
    --     name = "Interface channel",
    --     options = channels,
    --     default = 1
    -- }

    -- params:add {
    --     type = "option",
    --     id = "clock_device",
    --     name = "Clock device",
    --     options = {"no", "yes"},
    --     action = function(value)
    --         clock_device = value == 2
    --         if value == 1 then
    --             midi_device:stop()
    --         end
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "quantize_midi",
    --     name = "Quantize",
    --     options = {"no", "yes"},
    --     action = function(value)
    --         quantize_midi = value == 2
    --         Passthrough.build_scale()
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "scale_mode",
    --     name = "Scale",
    --     options = scale_names,
    --     default = 5,
    --     action = function()
    --         Passthrough.build_scale()
    --     end
    -- }

    -- params:add {
    --     type = "number",
    --     id = "root_note",
    --     name = "Root",
    --     min = 0,
    --     max = 11,
    --     default = 0,
    --     formatter = function(param)
    --         return MusicUtil.note_num_to_name(param:get())
    --     end,
    --     action = function()
    --         Passthrough.build_scale()
    --     end
    -- }

    -- expose device and interface connections
    Passthrough.device = midi_device
    Passthrough.interface = midi_interface
    
end

function launch_passthrough()
  if not first_init then
    devices = pt_core.get_midi_devices()
    midi_device = midi.connect(state.midi_device)
    midi_interface = midi.connect(state.midi_interface)
    
    passthrough_config = generate_param_config()
    Passthrough.init()
    
    midi_device.event = Passthrough.device_event
    midi_interface.event = Passthrough.interface_event
    
    first_init = true
  end
end

--
-- [optional] hooks are essentially callbacks which can be used by multiple mods
-- at the same time. each function registered with a hook must also include a
-- name. registering a new function with the name of an existing function will
-- replace the existing function. using descriptive names (which include the
-- name of the mod itself) can help debugging because the name of a callback
-- function will be printed out by matron (making it visible in maiden) before
-- the callback function is called.
--
-- here we have dummy functionality to help confirm things are getting called
-- and test out access to mod level state via mod supplied fuctions.
--

mod.hook.register("script_pre_init", "passthrough", function()
  -- tweak global environment here ahead of the script `init()` function being called
  launch_passthrough()
end)


--
-- [optional] menu: extending the menu system is done by creating a table with
-- all the required menu functions defined.
--

local m = {}


generate_param_config = function() 
  return {
  midi_device = {
    param_type = "option",
    id = "midi_device",
    name = "Midi Device",
    options = devices,
    action = function(value)
        midi_device.event = nil
        midi_device = midi.connect(value)
        midi_device.event = Passthrough.device_event
    end
  },
  midi_interface = {
    param_type = "option",
    id = "midi_interface",
    name = "Midi Interface",
    options = devices,
    action = function(value)
        midi_interface.event = nil
        midi_interface = midi.connect(value)
        midi_interface.event = Passthrough.interface_event
    end
  },
  device_channel = {
    param_type = "option",
    id = "device_channel",
    name = "Device channel",
    options = pt_core.device_channels
  },
  interface_channel = {
    param_type = "option",
    id = "interface_channel",
    name = "Interface channel",
    options = pt_core.interface_channels
  },
  cc_direction = {    
    param_type = "option",
    id = "cc_direction",
    name = "CC msg direction",
    options = pt_core.cc_directions
  },
  clock_device = {
    param_type = "option",
    id = "clock_device",
    name = "Clock device",
    options = pt_core.toggles,
    action = function(value)
        clock_device = value == 2
        if value == 1 then
            midi_device:stop()
        end
    end
    },
  quantize_midi = {
    param_type = "option",
    id = "quantize_midi",
    name = 'Quantize midi',
    options = pt_core.toggles,
    action = function(value)
        quantize_midi = value == 2
        current_scale = pt_core.build_scale(state.root_note, state.current_scale)
    end
  },
  root_note = {
    param_type = 'number',
    id = 'root_note',
    name = "Root note",
    minimum = 0,
    maximum = 11,
    formatter = pt_core.root_note_formatter,
    action = function()
        current_scale = pt_core.build_scale(state.root_note, state.current_scale)
    end
  },
  current_scale = {
      param_type = 'option',
      id = 'current_scale',
      name = 'Current scale',
      options = pt_core.scale_names,
      action = function()
        current_scale = pt_core.build_scale(state.root_note, state.current_scale)
      end
    }
}
end

local screen_order = {{"midi_device", "midi_interface", "device_channel", "interface_channel", "clock_device", "cc_direction"}, {'quantize_midi', 'root_note', 'current_scale'}}

local screen_delta = 1
local page = 1

function update_parameter(p, dir)
  -- update options
  if p.param_type == "option" then
    state[p.id] = util.clamp(state[p.id] + dir, 1, #p.options)
  end

  -- generate scale
  if p.param_type == 'number' then
    state[p.id] = util.clamp(state[p.id] + dir, p.minimum, p.maximum)
  end
  
  if p.action and type(p.action == 'function') then
    p.action(state[p.id])
  end
end

function format_parameter(p) 
  if p.formatter and type(p.formatter == 'function') then
    return p.formatter(state[p.id])
  else
    if p.param_type == "option" then
      return p.options[state[p.id]]
    end
    return state[p.id]
  end
end

m.key = function(n, z)
  if n == 2 and z == 1 then
    -- return to the mod selection menu
    mod.menu.exit()
  end
  if n == 3 and z == 1 then
    page = page == 1 and 2 or 1
    screen_delta = 1
    mod.menu.redraw()
  end
end


m.enc = function(n, d)
  if n == 2 then
    screen_delta = util.clamp(screen_delta + d, 1, #screen_order[page])
  end
  
  if n == 3 then
    local param = passthrough_config[screen_order[page][screen_delta]]
    update_parameter(param, d)
  end 
  mod.menu.redraw()
end


m.redraw = function()
  screen.clear()
  for index, value in ipairs(screen_order[page]) do
    screen.move(4, 10 * index)
    local param = passthrough_config[value]
    screen.level(index == screen_delta and 15 or 7)
    screen.text(param.name .. " " .. format_parameter(param))
  end
  
  screen.update()
end

m.init = function() 
  launch_passthrough()
  page = 1
  screen_delta = 1
  
end -- on menu entry, ie, if you wanted to start timers

m.deinit = function() end -- on menu exit

-- register the mod menu
--
-- NOTE: `mod.this_name` is a convienence variable which will be set to the name
-- of the mod which is being loaded. in order for the menu to work it must be
-- registered with a name which matches the name of the mod in the dust folder.
--
mod.menu.register(mod.this_name, m)


--
-- [optional] returning a value from the module allows the mod to provide
-- library functionality to scripts via the normal lua `require` function.
--
-- NOTE: it is important for scripts to use `require` to load mod functionality
-- instead of the norns specific `include` function. using `require` ensures
-- that only one copy of the mod is loaded. if a script were to use `include`
-- new copies of the menu, hook functions, and state would be loaded replacing
-- the previous registered functions/menu each time a script was run.
--
-- here we provide a single function which allows a script to get the mod's
-- state table. using this in a script would look like:
--
-- local mod = require 'name_of_mod/lib/mod'
-- local the_state = mod.get_state()
--
return Passthrough
