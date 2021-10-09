-- passthrough
--
-- library for passing midi
-- between connected ports
-- + scale quantizing
-- + user event callbacks
--
-- for how to use see example script

local Passthrough = {}
local core = require("passthrough/lib/core")
local utils = require("passthrough/lib/utils")

local tab = require "tabutil"
local mod = require "core/mods"

Passthrough.user_event = core.user_event

local function device_event(data, device)
    core.device_event(
      device.port,
      params:get("target_"..device.port),
      params:get("input_channel_"..device.port),
      params:get("output_channel_"..device.port),
      params:get("send_clock_"..device.port)==2,
      params:get("quantize_midi_"..device.port),
      params:get("current_scale_"..device.port),
      data)

    Passthrough.user_event(data, {name=device.name,port=device.port})
end

function Passthrough.init()
  if tab.contains(mod.loaded_mod_names(), "passthrough") then 
    print("Passthrough already running as mod")
    return 
  end

  core.setup_midi()
  
  port_amount = tab.count(core.midi_connections)
  params:add_group("PASSTHROUGH", 8*port_amount + 2)
  
  for k, v in pairs(core.midi_connections) do
      local name = utils.table_find_value(core.midi_ports, function(key, value) return value.port == v.port end).name
      params:add_separator(name .. ' ' .. v.port)

      params:add {
        type="number",
        id="target_" .. v.port,
        name = "Target",
        min=1,
        max = #core.available_targets,
        default = 1,
        action = function(value)
          connector = utils.table_find_value(core.midi_connections, function(key, val) return val.port == v.port end)
          connector.connect.event = nil
          connector.connect.event = function(data) 
            device = utils.table_find_value(core.midi_ports, function(key, val) return val.port == v.port end)
            if device_event then device_event(data, device) end
            if not device_event then
              print("no event found")
            end
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
        default=1,
        action = function(value)
            if value == 1 then
                core.stop_clocks(v.port)
            end
        end
      }
      params:add {
        type = "option",
        id = "quantize_midi_"..v.port,
        name = "Quantize midi",
        options = core.toggles
      }
      params:add {
        type = "number",
        id = "root_note_"..v.port,
        name = "Root",
        minimum = 0,
        maximum = 11,
        formatter = function(param) 
          return core.root_note_formatter(param:get())
        end,
        action = function()
            core.build_scale(params:get("root_note_"..v.port), params:get("current_scale_"..v.port), v.port)
        end
      }
      params:add {
          type = "option",
          id = "current_scale_"..v.port,
          name = "Scale",
          options = core.scale_names,
          action = function()
            core.build_scale(params:get("root_note_"..v.port), params:get("current_scale_"..v.port), v.port)
          end
        }

      end
      params:add_separator("All devices")
      params:add {
        type = "trigger",
        id = "midi_panic",
        name = "Midi panic",
        action = function()
          core.stop_all_notes()
        end
      }
  
  params:bang()
end

return Passthrough
