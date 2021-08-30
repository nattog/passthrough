local mod = require 'core/mods'

local core = require("passthrough/lib/core")
tab = require "tabutil"

local devices = {}
local clock_device
local send_clock
local quantize_midi
local current_scale = {}
local midi_device
local midi_interface

local api = {}
local running = false

api.user_device_event = core.user_device_event
api.user_interface_event = core.user_interface_event

local state = {
  midi_device = 1,
  device_channel=1,
  midi_interface = 2,
  interface_channel=1,
  target=1,
  input_channel=1, 
  output_channel = 1,
  send_clock=1,
  clock_device = 1,
  quantize_midi = 1,
  current_scale = 1,
  cc_direction = 1,
  root_note = 0,
  post_startup = false
}

local new_state = {}
for i=1, 16 do 
  table.insert(new_state, {
    target = 1,
    input_channel = 1,
    output_channel = 1,
    send_clock = 1,
    quantize_midi = 1,
    current_scale = 1,
    root_note = 1,
  })
end

-- local new_state = {
--   {
--     target = 1,
--     input_channel = 1,
--     output_channel = 1,
--     send_clock = 1,
--     quantize_midi = 1,
--     current_scale = 1,
--     root_note = 1,
--   },
--   {
--     target = 1,
--     input_channel = 1,
--     output_channel = 1,
--     send_clock = 1,
--     quantize_midi = 1,
--     current_scale = 1,
--     root_note = 1,
--   },
--   {
--     target = 1,
--     input_channel = 1,
--     output_channel = 1,
--     send_clock = 1,
--     quantize_midi = 1,
--     current_scale = 1,
--     root_note = 1,
--   },
--   {
--     target = 1,
--     input_channel = 1,
--     output_channel = 1,
--     send_clock = 1,
--     quantize_midi = 1,
--     current_scale = 1,
--     root_note = 1,
--   }
-- }

local passthrough_config = {
  target = {
    param_type = "option",
    id = "target",
    name = "Target",
    options = core.available_targets,
    formatter = function(value)
      return value == 1 and core.available_targets[value] or core.midi_ports[value-1]
    end
  },
  input_channel = {
    param_type = "option",
    id = "input_channel",
    name = "Input channel",
    options = core.device_channels
  },
  output_channel = {
    param_type = "option",
    id = "output_channel",
    name = "Output channel",
    options = core.interface_channels
  },
  send_clock = {
    param_type = "option",
    id = "send_clock",
    name = "Clock out",
    options = core.toggles,
    action = function(value)
        send_clock = value == 2
        -- if value == 1 then
        --     midi_device:stop()
        -- end
    end
    },
  quantize_midi = {
    param_type = "option",
    id = "quantize_midi",
    name = 'Quantize midi',
    options = core.toggles,
    action = function(value)
        quantize_midi = value == 2
        current_scale = core.build_scale(state.root_note, state.current_scale)
    end
  },
  root_note = {
    param_type = 'number',
    id = 'root_note',
    name = "Root",
    minimum = 0,
    maximum = 11,
    formatter = core.root_note_formatter,
    action = function()
        current_scale = core.build_scale(state.root_note, state.current_scale)
    end
  },
  current_scale = {
      param_type = 'option',
      id = 'current_scale',
      name = 'Scale',
      options = core.scale_names,
      action = function()
        current_scale = core.build_scale(state.root_note, state.current_scale)
      end
    }
}

local midi_add = _norns.midi.add

_norns.midi.add = function(id, name, dev)
  midi_add(id, name, dev)
  update_devices()
end

local midi_remove = _norns.midi.remove

_norns.midi.remove = function(id)
  midi_remove(id)
  update_devices()
end

local midi_connect = _norns.midi.connect

_norns.midi.connect = function(id)
    midi_connect(id)
end

function read_state() 
  local f = io.open(_path.data..'passthrough.state')
  if f ~= nil then
    io.close(f)
    state = dofile(_path.data..'passthrough.state')
  end

  current_scale = core.build_scale(state.root_note, state.current_scale)
end

mod.hook.register("system_post_startup", "read passthrough state", function()
  core.setup_midi()
  read_state()
end)

mod.hook.register("system_pre_shutdown", "write passthrough state", function()
  local f = io.open(_path.data..'passthrough.state',"w+")
  io.output(f)
  io.write("return { midi_device="..state.midi_device..',')
  io.write("device_channel="..state.device_channel..',')
  io.write("target="..state.target..',')
  io.write("midi_interface="..state.midi_interface..',')
  io.write("interface_channel="..state.interface_channel..',')
  io.write("clock_device="..state.clock_device..',')
  io.write("quantize_midi="..state.quantize_midi..',')
  io.write("current_scale="..state.current_scale..",")
  io.write("cc_direction="..state.cc_direction..",")
  io.write("root_note="..state.root_note.." }\n")
  io.close(f)
end)

mod.hook.register("script_post_cleanup", "passthrough post cleanup", function()
  launch_passthrough()
end)

function device_event(data, origin)
    core.device_event(origin, state.target, state.device_channel, state.interface_channel, state.quantize_midi, current_scale, data)
    api.user_device_event(data)
end

function interface_event(data)
  print('raw data from interface')
    core.interface_event(midi_device, state.device_channel, state.clock_device, state.cc_direction, data)
    api.user_interface_event(data)
end

function update_devices() 
  devices=core.get_midi_devices()
  core.setup_midi()
end

function launch_passthrough()
    running = true
    -- ensure devices is up to date for device options menu
    update_devices()
    core.setup_midi()

    -- connect state devices
end

-- function add_params()
--     params:add_group("PASSTHROUGH", 9)
--     params:add {
--         type = "option",
--         id = "midi_device",
--         name = "Device",
--         options = devices,
--         default = state.midi_device,
--         action = function(value)
--             state.midi_device = value
--             midi_device.event = nil
--             local existing_event = midi.vports[value].event and midi.vports[value].event or nil
--             midi_device = midi.connect(value)
--             midi_device.event = function(data) 
--               if existing_event then
--                 existing_event(data)
--               end
--               device_event(data)
--             end
--         end
--     }
--     params:add {
--         type = "option",
--         id = "target",
--         name = "Target",
--         options = core.available_targets,
--         default = state.target,
--         action = function(value)
--             state.target = value
--         end
--     }
--     params:add {
--         type = "option",
--         id = "midi_interface",
--         name = "Interface",
--         options = devices,
--         default = state.midi_interface,
--         action = function(value)
--             state.midi_interface = value
--             midi_interface.event = nil
--             local existing_event = midi.vports[value].event and midi.vports[value].event or nil
--             midi_interface = midi.connect(value)
--             midi_interface.event = function(data) 
--               if existing_event then
--                 existing_event(data)
--               end
--               interface_event(data) 
--             end
--         end
--     }
--     params:add {
--         type = "option",
--         id = "cc_direction",
--         name = "CC msg direction",
--         options = core.cc_directions,
--         default = state.cc_direction,
--         action = function(value)
--           state.cc_direction = value
--         end
--     }
--     params:add {
--         type = "option",
--         id = "device_channel",
--         name = "Device channel",
--         options = core.device_channels,
--         default = state.device_channel,
--         action = function(value)
--           state.device_channel = value
--         end
--     }
--     params:add {
--         type = "option",
--         id = "interface_channel",
--         name = "Interface channel",
--         options = core.interface_channels,
--         default = state.interface_channel,
--         action = function(value)
--           state.interface_channel = value
--         end
--     }
--     params:add {
--         type = "option",
--         id = "clock_device",
--         name = "Clock device",
--         options = core.toggles,
--         action = function(value)
--             state.clock_device = value
--             clock_device = value == 2
--             if value == 1 then
--                 midi_device:stop()
--             end
--         end
--     }
--     params:add {
--         type = "option",
--         id = "quantize_midi",
--         name = "Quantize",
--         options = {"no", "yes"},
--         action = function(value)
--             state.quantize_midi = value
--             quantize_midi = value == 2
--             current_scale = core.build_scale(state.root_note, state.current_scale)
--         end
--     }
    
--     params:add {
--         type = "number",
--         id = "root_note",
--         name = "Root",
--         min = 0,
--         max = 11,
--         default = 0,
--         formatter = function(param) 
--           return core.root_note_formatter(param:get())
--         end,
--         action = function(value)
--             state.root_note = value
--             current_scale = core.build_scale(state.root_note, state.current_scale)
--         end
        
--     }

--     params:add {
--         type = "option",
--         id = "current_scale",
--         name = "Current Scale",
--         options = core.scale_names,
--         default = 5,
--         action = function(value)
--             state.current_scale = value
--             current_scale = core.build_scale(state.root_note, state.current_scale)
--         end
--     }

--     core.params_added = true
-- end

mod.hook.register("script_pre_init", "passthrough", function()
  -- tweak global environment here ahead of the script `init()` function being called
  local script_init = init
  
  init = function()
      -- add_params()
      script_init()
      launch_passthrough()
  end
end)

local screen_order = {{"target", "input_channel", "output_channel", "send_clock", 'quantize_midi', 'root_note', 'current_scale'}}
local m = {
  list={"target", "input_channel", "output_channel", "send_clock", 'quantize_midi', 'root_note', 'current_scale'},
  pos=0,
  page=1,
  len=tab.count(screen_order[1])
}


local screen_delta = 1
local page = 1

function update_parameter(p, index, dir)
  -- update options
  if p.param_type == "option" then
    new_state[index][p.id] = util.clamp(new_state[index][p.id] + dir, 1, #p.options)
  end

  -- generate scale
  if p.param_type == 'number' then
    new_state[index][p.id] = util.clamp(new_state[index][p.id] + dir, p.minimum, p.maximum)
  end
  
  if p.action and type(p.action == 'function') then
    p.action(new_state[index][p.id])
  end
end

function format_parameter(p, index) 
  if p.formatter and type(p.formatter == 'function') then
    return p.formatter(new_state[index][p.id])
  end

  if p.param_type == "option" then
    return p.options[new_state[index][p.id]]
  end

  return state[p.id]
end

m.key = function(n, z)
  if n == 2 and z == 1 then
    mod.menu.exit()
  end
  if n == 3 and z == 1 then
    page = page + z > 3 and 1 or page + z
    screen_delta = 1
    mod.menu.redraw()
  end
end

m.enc = function(n, d)
  if n == 2 then
    m.pos = util.clamp(m.pos + d, 0, m.len - 1)
  end
  
  if n == 3 then
    update_parameter(passthrough_config[screen_order[page][m.pos + 1]], 1, d)
  end 
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  for i=1,6 do
    if (i > 2 - m.pos) and (i < m.len - m.pos + 3) then
      screen.move(0,10*i)
      local line = m.list[i+m.pos-2]
      local param = passthrough_config[line]
      if(i==3) then
        screen.level(15)
      else
        screen.level(4)
      end
      screen.text(param.name .. " : " .. format_parameter(param, 1))
    end
  end
  screen.rect(0, 0, 140, 13)
  screen.level(0)
  screen.fill()
  screen.level(15)
  screen.move(120, 10)
  screen.text_right(string.upper(core.midi_ports[page]))
  screen.update()
end

m.init = function() 
  page = 1
  screen_delta = 1
  
  launch_passthrough()
end

m.deinit = function() end

mod.menu.register(mod.this_name, m)

api.get_state = function()
  return state
end

return api
