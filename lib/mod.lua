local mod = require "core/mods"
local core = require("passthrough/lib/core")
local utils = require("passthrough/lib/utils")
local tab = require "tabutil"

local api = {}
local config = {}
local state = {}

-- MOD NORNS OVERRIDES --

local midi_add = _norns.midi.add
local midi_remove = _norns.midi.remove
local script_clear = norns.script.clear

_norns.midi.add = function(id, name, dev)
  midi_add(id, name, dev)
  update_devices()
end

_norns.midi.remove = function(id)
  midi_remove(id)
  update_devices()
end

norns.script.clear = function()
  script_clear()
  update_devices()
end

-- STATE FUNCTIONS --
function write_state()
  local f = io.open(_path.data.."passthrough.state","w+")
  io.output(f)
  io.write("return {")
  local counter = 0
  for k, v in pairs(state) do
    counter = counter + 1

    if counter~=1 then
      io.write(",")
    end
    io.write("["..k.."] =")
    io.write("{ active="..v.active..",")
    io.write("dev_port="..v.dev_port..",")
    io.write("target="..v.target..",")
    io.write("input_channel="..v.input_channel..",")
    io.write("output_channel="..v.output_channel..",")
    io.write("send_clock="..v.send_clock..",")
    io.write("quantize_midi="..v.quantize_midi..",")
    io.write("current_scale="..v.current_scale..",")
    io.write("root_note="..v.root_note.."}")
  end
  io.write("}\n")
  io.close(f)
end

function read_state() 
  local f = io.open(_path.data.."passthrough.state")
  if f ~= nil then
    io.close(f)
    state = dofile(_path.data.."passthrough.state")
  end

  for i = 1, tab.count(state) do
    core.build_scale(state[i].root_note, state[i].current_scale, state[i].dev_port)
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

  for k, v in pairs(core.ports) do
    if state[v.port] == nil then
      state[v.port] = {
        active = 1,
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
      state[v.port].dev_port = v.port
    end
    
    -- config creates an object for each passthru parameter
    config[k] = {
      active = {
        param_type = "option",
        id = "active",
        name = "Active",
        options = core.toggles
      },
      target = {
        param_type = "option",
        id = "target",
        name = "Target",
        options = core.targets[v.port],
        action = function(value)
          core.port_connections[v.port] = core.set_target_connections(v.port, value)
        end,
        formatter = function(value)
          if value == 1 then return core.targets[v.port][value] end
          local target = core.targets[v.port][value]
          local found_port = utils.table_find_value(core.ports, function(_,v) return target == v.port end)
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
        name = "Quantize midi",
        options = core.toggles
      },
      root_note = {
        param_type = "number",
        id = "root_note",
        name = "Root",
        minimum = 0,
        maximum = 11,
        formatter = core.root_note_formatter,
        action = function()
            core.build_scale(state[k].root_note, state[k].current_scale, k)
        end
      },
      current_scale = {
          param_type = "option",
          id = "current_scale",
          name = "Scale",
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

function device_event(id, data)
    local port = core.get_port_from_id(id)
    port_config = state[port]
    
    print(port)
    

    if port_config ~= nil and port_config.active == 2 then
      core.device_event(
        port,
        port_config.target,
        port_config.input_channel,
        port_config.output_channel,
        port_config.send_clock,
        port_config.quantize_midi,
        port_config.current_scale,
        data)
      
      api.user_event(id, data)
    end
end

core.origin_event = device_event -- assign device_event to core origin

function update_devices() 
  core.setup_midi()
  config = create_config()
  assign_state()
end

function update_parameter(p, index, dir)
  -- update options
  if p.param_type == "option" then
    state[index][p.id] = util.clamp(state[index][p.id] + dir, 1, #p.options)
  end

  -- generate scale
  if p.param_type == "number" then
    state[index][p.id] = util.clamp(state[index][p.id] + dir, p.minimum, p.maximum)
  end

  if p.action and type(p.action == "function") then
    p.action(state[index][p.id])
  end

  write_state()
end

function format_parameter(p, index) 
  if p.formatter and type(p.formatter == "function") then
    return p.formatter(state[index][p.id])
  end

  if p.param_type == "option" then
    return p.options[state[index][p.id]]
  end

  return state[index][p.id]
end

local get_menu_pagination_table = function()
    local t = {}
    
    local counter = 1
    for k, v in pairs(config) do
      t[counter] = k
      counter = counter + 1
    end
    
    return t
end

-- MOD MENU --
local screen_order = {"active", "target", "input_channel", "output_channel", "send_clock", "quantize_midi", "root_note", "current_scale", "midi_panic"}
local m = {
  list=screen_order,
  pos=0,
  page=1,
  len=tab.count(screen_order),
  show_hint = true,
  display_panic = false,
  display_devices = {}
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
    m.page = util.wrap(m.page + z, 1, tab.count(m.display_devices))
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
    local page_port = m.display_devices[m.page]
    if m.list[m.pos+1] == "midi_panic" then
      core.stop_all_notes()
      toggle_display_panic()
    else
      update_parameter(config[page_port][m.list[m.pos + 1]], page_port, d)
    end
  end 
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  local page_port = m.display_devices[m.page]
  for i=1,6 do
    if (i > 2 - m.pos) and (i < m.len - m.pos + 3) then
      screen.move(0,10*i)
      local line = m.list[i+m.pos-2]
      if(i==3) then
        screen.level(15)
      else
        screen.level(4)
      end

      if line == "midi_panic" then
        screen.text("Midi panic : ")
        screen.rect(50, (10*i)-4.5, 5, 5)
        screen.level(m.display_panic and 15 or 4)
        screen.fill()
      else
        local param = config[page_port][line]
        screen.text(param.name .. " : " .. format_parameter(param, page_port))
      end
    end
  end
  screen.rect(0, 0, 140, 13)
  screen.level(0)
  screen.fill()
  screen.level(15)
  screen.move(0, 10)
  screen.text(page_port)
  screen.move(120, 10)
  screen.text_right(string.upper(core.ports[page_port].name))
  if m.show_hint then
    screen.level(2)
    screen.move(0, 20)
    screen.text("E2 scroll")
    screen.move(42, 20)
    screen.text("E3 select")
    screen.move(120, 20)
    screen.text_right("K3 port")
  end
  screen.update()
end

m.init = function()
  m.page = 1
  m.pos = 0
  m.show_hint=true
  update_devices()
  m.display_devices = get_menu_pagination_table()
end

m.deinit = function() 
  write_state()
end

mod.menu.register(mod.this_name, m)

-- API --
api.get_state = function()
  return state
end

api.get_connections = function()
  return core.port_connections
end

api.get_port_from_id = function(id)
  return core.get_port_from_id(id)
end

api.get_ports = function()
  if core.debug then
    for k, v in pairs(core.ports) do
      tab.print(v)
    end
  end
  return core.ports
end

api.set_debug = function(v)
  core.debug = v
end

api.user_event = core.user_event

return api
