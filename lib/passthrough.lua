-- passthrough
--
-- library for passing midi
-- between connected ports
-- + scale quantizing
-- + user event callbacks
--
-- for how to use see example
--
-- PRs welcome

local Passthrough = {}
local core = require("passthrough/lib/core")
local utils = require('passthrough/lib/util')

local tab = require "tabutil"
local mod = require 'core/mods'

Passthrough.user_event = core.user_event
  

function device_event(data, origin)
    core.device_event(
      origin,
      params:get('target_'..origin),
      params:get('input_channel_'..origin),
      params:get('output_channel_'..origin),
      params:get('send_clock_'..origin),
      params:get('quantize_midi_'..origin),
      params:get('current_scale_'..origin),
      data)

    device = core.midi_ports[origin]
    
    Passthrough.user_event(data, {name=device.name,port=device.port})
end

function build_scale()
    current_scale = core.build_scale(params:get("root_note"), params:get("scale_mode"))
end

function Passthrough.init()
  if tab.contains(mod.loaded_mod_names(), 'passthrough') then 
    print('Passthrough already running as mod')
    return 
  end

  core.setup_midi()
  
  core_length = tab.count(core.midi_ports)
  params:add_group("PASSTHROUGH", 8*core_length)
  
  for k, v in pairs(core.midi_ports) do
      params:add_separator(v.name)
      
      params:add {
        type="number",
        id='target_' .. v.port,
        name = "Target",
        min=1,
        max = #core.available_targets,
        default = 1,
        action = function(value)
          core.midi_connections[k].connect.event = function(data) 
            device_event(data, k)
          end
          core.port_connections[v.port] = core.get_target_connections(v.port, value)
        end,
        formatter = function(param)
          value = param:get()
          if value == 1 then 
            return core.available_targets[value] 
          else
            found_port = utils.table_find_value(core.midi_ports, function(key, val) return val.port == value - 1 end)
            if found_port then return found_port.name end
            return "Saved port unconnected"
          end
        end,
      }
      
      params:add {
        type = "option",
        id = "input_channel_"..v.port,
        name = "Input channel",
        options = core.input_channels
      }
      params:add {
        type = "option",
        id = "output_channel_"..v.port,
        name = "Output channel",
        options = core.output_channels
      }
      params:add {
        type = "option",
        id = "send_clock_"..v.port,
        name = "Clock out",
        options = core.toggles,
        action = function(value)
            if value == 1 then
                core.stop_clocks(v.port)
            end
        end
      }
      params:add {
        type = "option",
        id = "quantize_midi_"..v.port,
        name = 'Quantize midi',
        options = core.toggles
      }
      params:add {
        type = 'number',
        id = 'root_note_'..v.port,
        name = "Root",
        minimum = 0,
        maximum = 11,
        formatter =  function(param) 
          return core.root_note_formatter(param:get())
        end,
        action = function()
            core.build_scale(params:get('root_note_'..v.port), params:get('current_scale_'..v.port), k)
        end
      }
      params:add {
          type = 'option',
          id = 'current_scale_'..v.port,
          name = 'Scale',
          options = core.scale_names,
          action = function()
            core.build_scale(params:get('root_note_'..v.port), params:get('current_scale_'..v.port), k)
          end
        }
  end
  params:bang()
end

return Passthrough
