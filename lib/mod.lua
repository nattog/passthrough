local mod = require 'core/mods'

local core = require("passthrough/lib/core")
tab = require "tabutil"

local api = {}
local clock_messages = {"clock", "start", "stop", "continue"}
local display_panic = false

local config = {}

api.user_device_event = core.user_device_event

local state = {}

create_config = function()
  local config={}
  for port = 1, tab.count(core.midi_ports) do
    -- if no state exists for this port, create a new one
    if state[port] == nil then
      print('no state saved for port, adding defaults')
      state[port] = {
        target = 1,
        input_channel = 1,
        output_channel = 1,
        send_clock = 1,
        quantize_midi = 1,
        current_scale = 1,
        root_note = 0
      }
    end
    
    -- config creates an object for each passthru parameter
    config[port] = {
      target = {
        param_type = "option",
        id = "target",
        name = "Target",
        options = core.available_targets,
        action = function(value)
          local existing_event = core.midi_connections[port].event
          core.midi_connections[port].event = function(data) 
            device_event(data, port)
          end
        end,
        formatter = function(value)
          return value == 1 and core.available_targets[value] or core.midi_ports[value-1]
        end
      },
      input_channel = {
        param_type = "option",
        id = "input_channel",
        name = "Input channel",
        options = core.input_channels
      },
      output_channel = {
        param_type = "option",
        id = "output_channel",
        name = "Output channel",
        options = core.output_channels
      },
      send_clock = {
        param_type = "option",
        id = "send_clock",
        name = "Clock out",
        options = core.toggles,
        action = function(value)
            if value == 1 then
                core.stop_clocks(origin, state[port].target)
            end
        end
        },
      quantize_midi = {
        param_type = "option",
        id = "quantize_midi",
        name = 'Quantize midi',
        options = core.toggles
      },
      root_note = {
        param_type = 'number',
        id = 'root_note',
        name = "Root",
        minimum = 0,
        maximum = 11,
        formatter = core.root_note_formatter,
        action = function()
            core.build_scale(state[port].root_note, state[port].current_scale, port)
        end
      },
      current_scale = {
          param_type = 'option',
          id = 'current_scale',
          name = 'Scale',
          options = core.scale_names,
          action = function()
            core.build_scale(state[port].root_note, state[port].current_scale, port)
          end
        }
    }

    config[port].target.action(state[port].target)
    config[port].root_note.action(state[port].root_note, state[port].current_scale, port)
    config[port].current_scale.action(state[port].root_note, state[port].current_scale, port)
  end

  return config
end

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

local script_clear = norns.script.clear

norns.script.clear = function()
  script_clear()
  launch_passthrough()
end

function write_state()
  local f = io.open(_path.data..'passthrough.state',"w+")
  io.output(f)
  io.write("return {")
  for i =1, tab.count(state) do
    local port_config = state[i]
    if i~=1 then
      io.write(",")
    end
    io.write("{ target="..port_config.target..",")
    io.write("input_channel="..port_config.input_channel..",")
    io.write("output_channel="..port_config.output_channel..",")
    io.write("send_clock="..port_config.send_clock..",")
    io.write("quantize_midi="..port_config.quantize_midi..",")
    io.write("current_scale="..port_config.current_scale..",")
    io.write("root_note="..port_config.root_note.."}")
  end
  io.write("}\n")
  io.close(f)
end

function read_state() 
  local f = io.open(_path.data..'passthrough.state')
  if f ~= nil then
    io.close(f)
    state = dofile(_path.data..'passthrough.state')
  end

  for i = 1, tab.count(state) do
    core.build_scale(state[i].root_note, state[i].current_scale, i)
  end
end

function assign_state()
  for i=1, tab.count(config) do
    if state[i] then
      for k, v in ipairs(state[i]) do
        config[k].action(v)
      end
    end
  end
end

mod.hook.register("system_post_startup", "read passthrough state", function()
  read_state()
  launch_passthrough()
end)

mod.hook.register("system_pre_shutdown", "write passthrough state", function()
  write_state()
end)

mod.hook.register("script_post_cleanup", "passthrough post cleanup", function()
  launch_passthrough()
end)

function device_event(data, origin)
    core.device_event(origin, state[origin].target, state[origin].input_channel, state[origin].output_channel, state[origin].send_clock, state[origin].quantize_midi, state[origin].current_scale, data)

    -- filter unwanted clock events
    if state[origin].send_clock == 1 and #data and tab.contains(clock_messages, midi.to_msg(data).type) then return end
    api.user_device_event(data)
end

function update_devices() 
  core.setup_midi()
  config = create_config()
  assign_state()
end

function launch_passthrough()
    update_devices()
end

mod.hook.register("script_pre_init", "passthrough", function()
  -- tweak global environment here ahead of the script `init()` function being called
  local script_init = init
  
  init = function()
      script_init()
      launch_passthrough()
  end
end)

local screen_order = {"target", "input_channel", "output_channel", "send_clock", 'quantize_midi', 'root_note', 'current_scale', 'midi_panic'}
local m = {
  list=screen_order,
  pos=0,
  page=1,
  len=tab.count(screen_order),
  show_hint = true
}

function update_parameter(p, index, dir)
  -- update options
  if p.param_type == "option" then
    state[index][p.id] = util.clamp(state[index][p.id] + dir, 1, #p.options)
  end

  -- generate scale
  if p.param_type == 'number' then
    state[index][p.id] = util.clamp(state[index][p.id] + dir, p.minimum, p.maximum)
  end
  
  if p.action and type(p.action == 'function') then
    p.action(state[index][p.id])
  end

  write_state()
end

function format_parameter(p, index) 
  if p.formatter and type(p.formatter == 'function') then
    return p.formatter(state[index][p.id])
  end

  if p.param_type == "option" then
    return p.options[state[index][p.id]]
  end

  return state[index][p.id]
end

m.key = function(n, z)
  if n == 2 and z == 1 then
    mod.menu.exit()
  end
  if n == 3 and z == 1 then
    m.page = util.wrap(m.page + z, 1, tab.count(config))
    m.pos = 0
    m.show_hint = false
    mod.menu.redraw()
  end
end

m.enc = function(n, d)
  m.show_hint = false
  if n == 2 then
    m.pos = util.clamp(m.pos + d, 0, m.len - 1)
  end
  
  if n == 3 then
    if screen_order[m.pos+1] == 'midi_panic' then
      core.stop_all_notes()
      display_panic=true
      clock.run(function()
        clock.sleep(0.5)
        display_panic=false
        mod.menu.redraw()
      end)
    else
      update_parameter(config[m.page][screen_order[m.pos + 1]], m.page, d)
    end
  end 
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  for i=1,6 do
    if (i > 2 - m.pos) and (i < m.len - m.pos + 3) then
      screen.move(0,10*i)
      local line = m.list[i+m.pos-2]
      if(i==3) then
        screen.level(15)
      else
        screen.level(4)
      end

      if line == 'midi_panic' then
        screen.text("Midi panic : ")
        screen.rect(50, (10*i)-4.5, 5, 5)
        screen.level(display_panic and 15 or 4)
        screen.fill()
      else
        local param = config[m.page][line]
        screen.text(param.name .. " : " .. format_parameter(param, m.page))
      end
    end
  end
  screen.rect(0, 0, 140, 13)
  screen.level(0)
  screen.fill()
  screen.level(15)
  screen.move(120, 10)
  screen.text_right(string.upper(core.midi_ports[m.page]))
  if m.show_hint then
    screen.level(2)
    screen.move(0, 20)
    screen.text('E2 scroll')
    screen.move(120, 20)
    screen.text_right('E3 select')
    screen.move(0, 10)
    screen.text("K3 port")
  end
  screen.update()
end

m.init = function() 
  m.page = 1
  m.pos = 0
  m.show_hint=true
  launch_passthrough()
end

m.deinit = function() 
  write_state()
end

mod.menu.register(mod.this_name, m)

api.get_state = function()
  return state
end

return api
