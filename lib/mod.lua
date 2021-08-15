local mod = require 'core/mods'


local pt_core = require("passthrough/lib/core")
local Passthrough = {}
tab = require "tabutil"

local first_init = false
local devices = {}
local clock_device
local quantize_midi
local current_scale = {}
local midi_device
local midi_interface

local passthrough_config = {}

local state = {
  midi_device = 1,
  device_channel=1,
  midi_interface = 2,
  interface_channel=1,
  clock_device = 1,
  quantize_midi = 1,
  current_scale = 1,
  cc_direction = 1,
  root_note = 0,
  post_startup = false
}

local midi_add = _norns.midi.add
_norns.midi.add = function(id, name, dev)
  midi_add(id, name, dev)
  devices = pt_core.get_midi_devices()
  read_state()
  launch_passthrough()
end

local midi_remove = _norns.midi.remove
_norns.midi.remove = function(id, name, dev)
  midi_remove(id, name, dev)
  devices = pt_core.get_midi_devices()
  launch_passthrough()
  print('midi_remove')
end

function read_state() 
  local f = io.open(_path.data..'passthrough.state')
  if f ~= nil then
    io.close(f)
    state = dofile(_path.data..'passthrough.state')
  end
end

mod.hook.register("system_post_startup", "read passthrough state", function()
  read_state()
  midi_device = midi.connect(state.midi_device)
  midi_interface = midi.connect(state.midi_interface)
  launch_passthrough()
  print('system post startup')
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

function Passthrough.user_device_event(data)
  print('user-device-event')
end

function Passthrough.user_interface_event(data)
  print('user-interface-event')
end

function Passthrough.device_event(data)
    print('device event')
    pt_core.device_event(midi_interface, state.device_channel, state.interface_channel, state.quantize_midi, current_scale, data)
    Passthrough.user_device_event(data)
end

function Passthrough.interface_event(data)
    print('interface event')
    pt_core.interface_event(midi_device, state.device_channel, state.clock_device, state.cc_direction, data)
    Passthrough.user_interface_event(data)
end

function launch_passthrough()
    print('launching passthrough')
    passthrough_config = generate_param_config()
    
    local device_param = passthrough_config['midi_device']
    local interface_param = passthrough_config['midi_interface']
    
    device_param.action(state.midi_device)
    interface_param.action(state.midi_interface)
    
    print("          ")
    print(state.midi_device)
    print(state.midi_interface)
    print("          ")
    print(midi_device.name .. (midi_device.connected and 'true' or 'false'))
    print("          ")
    print(midi_interface.name .. (midi_interface.connected and 'true' or 'false'))
    print("          ")
    print("\n-- passthru ready --\n")
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
  local script_init = init
  
  init = function()
      script_init()
      midi_device = midi.connect(state.midi_device)
      midi_interface = midi.connect(state.midi_interface)
      
      print("          ")
      print(state.midi_device)
      print(state.midi_interface)
      print("          ")
      print(midi_device.name .. (midi_device.connected and 'true' or 'false'))
      print("          ")
      print(midi_interface.name .. (midi_interface.connected and 'true' or 'false'))
      print("          ")

  end
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
        if midi_device then
          midi_device.event = nil
        end
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
        if midi_interface then
          midi_interface.event = nil
        end
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
  end
  
  if p.param_type == "option" then
    return p.options[state[p.id]]
  end
  
  return state[p.id]
end

m.key = function(n, z)
  if n == 2 and z == 1 then
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
    update_parameter(passthrough_config[screen_order[page][screen_delta]], d)
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
  page = 1
  screen_delta = 1
  
  midi_device = midi.connect(state.midi_device)
  midi_interface = midi.connect(state.midi_interface)
  
  tab.print(state)
  tab.print(midi_device)
  tab.print(midi_interface)
  tab.print(passthrough_config)
end

m.deinit = function() end


mod.menu.register(mod.this_name, m)

local api = {}

api.get_state = function()
  return state
end

return api
