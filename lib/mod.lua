local mod = require 'core/mods'

local core = require("passthrough/lib/core")
local utils = require("passthrough/lib/utils")
local tab = require "tabutil"

local api = {}
local config = {}
local state = {}

-- NORNS OVERRIDES --

local midi_add = _norns.midi.add
local midi_remove = _norns.midi.remove
local midi_connect = _norns.midi.connect
local script_clear = norns.script.clear

_norns.midi.add = function(id, name, dev)
  midi_add(id, name, dev)
  update_devices()
end

_norns.midi.remove = function(id)
  midi_remove(id)
  launch_passthrough()
end

_norns.midi.connect = function(id)
    midi_connect(id)
end

norns.script.clear = function()
  script_clear()
  update_devices()
end

-- STATE FUNCTIONS --
function write_state()
  local f = io.open(_path.data..'passthrough.state',"w+")
  io.output(f)
  io.write("return {")
  local counter = 0
  for k, v in pairs(state) do
    counter = counter + 1
    local port_config = state[k]
    if counter~=1 then
      io.write(",")
    end
    io.write('['..k..'] =')
    io.write("{ dev_port="..port_config.dev_port..",")
    io.write("target="..port_config.target..",")
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

-- HOOKS --
mod.hook.register("system_post_startup", "read passthrough state", function()
  read_state()
  update_devices()
end)

mod.hook.register("system_pre_shutdown", "write passthrough state", function()
  write_state()
end)

mod.hook.register("script_post_cleanup", "passthrough post cleanup", function()
  update_devices()
end)

mod.hook.register("script_pre_init", "passthrough", function()
  -- tweak global environment here ahead of the script `init()` function being called
  local script_init = init
  
  init = function()
      script_init()
      update_devices()
  end
end)


-- ACTIONS + EVENTS --
function create_config()
  local config={}
  for k, v in pairs(core.midi_ports) do
    -- if no state exists for this port, create a new one
    if state[k] == nil then
      print('No state saved for port, adding defaults')
      state[k] = {
        dev_port = v.port,
        target = 1,
        input_channel = 1,
        output_channel = 1,
        send_clock = 1,
        quantize_midi = 1,
        current_scale = 1,
        root_note = 0
      }
    else
      state[k].dev_port = v.port
    end
    
    -- config creates an object for each passthru parameter
    config[k] = {
      target = {
        param_type = "option",
        id = "target",
        name = "Target",
        options = core.available_targets,
        action = function(value)
          core.midi_connections[k].connect.event = function(data) 
            device_event(data, k)
          end
          
          core.port_connections[v.port] = core.get_target_connections(v.port, value)
        end,
        formatter = function(value)
          if value == 1 then return core.available_targets[value] end
          found_port = utils.table_find_value(core.midi_ports, function(key, val) return val.port == value - 1 end)
            
          if found_port then return found_port.name end
          return "Saved port unconnected"
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
                core.stop_clocks(v.port)
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
            core.build_scale(state[k].root_note, state[k].current_scale, k)
        end
      },
      current_scale = {
          param_type = 'option',
          id = 'current_scale',
          name = 'Scale',
          options = core.scale_names,
          action = function()
            core.build_scale(state[k].root_note, state[k].current_scale, k)
          end
        }
    }

    config[k].target.action(state[k].target)
    config[k].root_note.action(state[k].root_note, state[k].current_scale, k)
    config[k].current_scale.action(state[k].root_note, state[k].current_scale, k)
  end

  return config
end

function device_event(data, origin)
    core.device_event(
      origin,
      state[origin].target,
      state[origin].input_channel,
      state[origin].output_channel,
      state[origin].send_clock,
      state[origin].quantize_midi,
      state[origin].current_scale,
      data)

    device = core.midi_ports[origin]
    
    api.user_event(data, {name=device.name,port=device.port})
end

function update_devices() 
  core.setup_midi()
  config = create_config()
  assign_state()
end

function launch_passthrough()
    update_devices()
end

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


-- MOD MENU --
local screen_order = {"target", "input_channel", "output_channel", "send_clock", 'quantize_midi', 'root_note', 'current_scale', 'midi_panic'}
local m = {
  list=screen_order,
  pos=0,
  page=1,
  len=tab.count(screen_order),
  show_hint = true,
  display_panic = false
}

local toggle_display_panic = function()
  clock.run(function()
      m.display_panic=true
      clock.sleep(0.5)
      m.display_panic=false
      mod.menu.redraw()
  end)
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
    if m.pos == 0 and d == -1 then
      m.show_hint = true
    end
    m.pos = util.clamp(m.pos + d, 0, m.len - 1)
  end

  if n == 3 then
    if m.list[m.pos+1] == 'midi_panic' then
      core.stop_all_notes()
      toggle_display_panic()
    else
      update_parameter(config[m.page][m.list[m.pos + 1]], m.page, d)
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
        screen.level(m.display_panic and 15 or 4)
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
  screen.text_right(string.upper(core.midi_ports[m.page].name))
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
  update_devices()
end

m.deinit = function() 
  write_state()
end

mod.menu.register(mod.this_name, m)

-- API --
api.get_state = function()
  return state
end

api.user_event = core.user_event

return api
