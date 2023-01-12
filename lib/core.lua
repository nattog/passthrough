local MusicUtil = require "musicutil"
local pt = {}
local utils = require("passthrough/lib/utils")

pt.midi_panic_active = false
pt.input_channels = {"No change"}
pt.output_channels = {"Device src."}
pt.toggles = {"no", "yes"}
pt.scales = {}
pt.cc_limits = {"Pass all", "Pass none"}
local crow_output_options = {"Off", "1+2", "3+4"}
pt.crow_notes = crow_output_options
pt.crow_cc_outputs = crow_output_options
pt.crow_cc_options = {"Off"}

local crow_outputs = {"Off", "1", "2", "3", "4"}

local current_crow_note = nil

local current_crow_notes = {}

for i = 1, 128 do table.insert(pt.crow_cc_options, i) end
for i = 1, 10 do table.insert(pt.cc_limits, i) end
local active_notes = {}
local cc_limit_count = {}
local cc_limit_init = {}

id_port_lookup = {} -- used to lookup midi port by id
pt.port_connections = {} -- used to quickly grab table of targets for each port
pt.ports = {} -- port settings, id, name, port, connect
pt.targets = {} -- assign available targets (filters out itself) for each port

pt.origin_event = function (id, data) end
pt.has_devices = false

-- CORE NORNS OVERRIDES --
local midi_event = _norns.midi.event

_norns.midi.event = function(id, data)
  midi_event(id, data)
  pt.origin_event(id, data) -- passthrough
end

-- SCALE SETUP --
pt.scale_names = {}
for i = 1, #MusicUtil.SCALES do
    table.insert(pt.scale_names, string.lower(MusicUtil.SCALES[i].name))
end

pt.build_scale = function(root, scale, index)
    pt.scales[index] = MusicUtil.generate_scale_of_length(root, scale, 128)
end

-- CC LIMIT --
local function cc_limit_send(msg, target, out_ch, cc_limit)
    if cc_limit == 2 then
        return
    end

    if cc_limit == 1 then
        target:cc(msg.cc, msg.val, out_ch)
        return
    end

    if cc_limit_count[target] == nil then
        cc_limit_count[target] = 0
    end

    if cc_limit_count[target] < cc_limit - 2 then
        target:cc(msg.cc, msg.val, out_ch)
        cc_limit_count[target] = cc_limit_count[target] + 1
    else
        if cc_limit_init[target] == nil then
          cc_limit_init[target] = {}
        end
        if cc_limit_init[target][out_ch] == nil then
            cc_limit_init[target][out_ch] = {}
        end

        cc_limit_init[target][out_ch][msg.cc] = msg.val
    end
end

-- MIDI DEVICE DETECTION --
for i = 1, 16 do
    table.insert(pt.input_channels, i)
    table.insert(pt.output_channels, i)
end

pt.get_port_from_id = function(id) return id_port_lookup[id] end

pt.set_target_connections = function(origin, selection) 
  local t = {}

  -- SELECT ALL PORTS
  if selection == 1 then
    for k, v in pairs(pt.ports) do
      if v.port ~= origin then
        table.insert(t, v.connect)  
      end
    end

    return t
  else
    -- SINGLE PORT - still create iterable for ease
    local port_target = pt.targets[origin][selection]
    if origin ~= port_target then
      local mc = utils.table_find_value(pt.ports, function(k, v) return v.port == port_target end)
      if mc then table.insert(t, mc.connect) end
    end
  end
  
  return t
end

local create_port_targets_table = function(port)
  local t = {"all"}
  
  for k, v in pairs(pt.ports) do
    if port ~= v.port then
      table.insert(t, v.port)
    end
  end
  
  return t
end

pt.setup_midi = function()
    local id_port_map = {}
    local midi_ports={}
    local ports = {}
    local targets = {}

    for _,dev in pairs(midi.devices) do
        if dev.port~=nil then
            id_port_map[dev.id] = dev.port
            ports[dev.port] = {id=dev.id, name=dev.name, port=dev.port, connect=midi.connect(dev.port)}            
        end
    end

    pt.ports = ports
    pt.has_devices = tab.count(ports)>0
    
    for k, v in pairs(pt.ports) do
      local port_targets = create_port_targets_table(v.port)
      targets[v.port] = port_targets
    end
    
    id_port_lookup = id_port_map

    pt.targets = targets

    metro.init(pt.handle_cc_limit, 0.025):start()
end

pt.root_note_formatter = MusicUtil.note_num_to_name

-- EVENTS ON MENU CHANGE --
pt.remove_active_note = function(target, note, ch)
    local i = 1
    while i <= #active_notes do
        if active_notes[i][1] == target and active_notes[i][2] == note and active_notes[i][3] == ch then
            table.remove(active_notes, i)
        end
        i = i+1
    end
end

pt.stop_clocks = function(origin)
    local msg = {type="stop"}
    local connections = pt.port_connections[origin]
    for k, v in pairs(connections) do
      pt.handle_clock_data(msg, v)
    end
end

pt.stop_all_notes = function()
    if #active_notes then
        for i=1, #active_notes do
            active_notes[i][1]:note_off(active_notes[i][2], 0, active_notes[i][3])
        end
    end
    active_notes= {}
end

-- CROW DATA
pt.crow_note_on_data = function(note_num, note_channel, gate_channel)
    current_crow_note = note_num
    crow.output[note_channel].volts = utils.n2v(note_num)
    crow.output[gate_channel].action = "{to(5,0)}"
    crow.output[gate_channel].execute()
end

pt.crow_note_off_data = function(note_num, gate_channel)
    if current_crow_note == nil or current_crow_note == note_num then
        crow.output[gate_channel].action = "{to(0,0)}"
        crow.output[gate_channel].execute()
        current_crow_note = nil
    end
end

pt.crow_cc_data = function(msg, channel)
   crow.output[channel].volts = utils.cc_cv(msg.val)
end

pt.quantize_note_data = function(note, current_scale)
    if note ~= nil then
        note = MusicUtil.snap_note_to_array(note, current_scale)
    end

    return note
end

-- DATA HANDLERS --
pt.handle_midi_data = function(msg, target, out_ch, quantize_midi, current_scale, cc_limit)
    local note = (quantize_midi == 2 and msg.note ~= nil) and pt.quantize_note_data(msg.note, current_scale) or msg.note

    if msg.type == "note_off" then
        target:note_off(note, 0, out_ch)
        pt.remove_active_note(target, note, out_ch)
    elseif msg.type == "note_on" then
        target:note_on(note, msg.vel, out_ch)
        table.insert(active_notes,{target,note,out_ch})
    elseif msg.type == "key_pressure" then
        target:key_pressure(note, msg.val, out_ch)
    elseif msg.type == "channel_pressure" then
        target:channel_pressure(msg.val, out_ch)
    elseif msg.type == "pitchbend" then
        target:pitchbend(msg.val, out_ch)
    elseif msg.type == "program_change" then
        target:program_change(msg.val, out_ch)
    elseif msg.type == "cc" then
        cc_limit_send(msg, target, out_ch, cc_limit)
    end
end

pt.crow_note_on(note, output)
    current_crow_notes[output] = note
    crow.output[output].volts = utils.n2v(note)
end

pt.crow_gate_on(output)
    crow.output[output].action = "{to(5,0)}"
    crow.output[output].execute()
end

pt.crow_gate_off(note, output)
    if current_crow_notes[output] == nil or current_crow_notes[output] == note then
        crow.output[output].action = "{to(0,0)}"
        crow.output[output].execute()
        current_crow_notes[output] = nil
    end
end

pt.process_crow = function(msg, options)
    -- 1 = {
    --     note = false,
    --     gate = false,
    --     velocity = false,
    --     cc = "off",
    --     clock = false,
    --   },
    outputs, quantize_midi, current_scale = table.unpack(options)

    for k, v in pairs(outputs) do
        if msg.note ~= nil and v.note == true then
            local note = quantize_midi == 2 and pt.quantize_note_data(msg.note, current_scale) or msg.note
            if (msg.type == "note_on") then
                pt.crow_note_on_data(note, k) -- note and output number
            end
        end
    end
    
    if (crow_notes > 1) then
        local note = (quantize_midi == 2 and msg.note ~= nil) and pt.quantize_note_data(msg.note, current_scale) or msg.note

    end
end

pt.process_data_for_crow = function(msg, crow_notes, crow_cc_outputs, crow_cc_selection_a, crow_cc_selection_b, quantize_midi, current_scale)
    local note = (quantize_midi == 2 and msg.note ~= nil) and pt.quantize_note_data(msg.note, current_scale) or msg.note
    
    if (crow_notes > 1) then
        local is_first_output_pair = crow_notes == 2
        if msg.type == "note_on" then
            local note_channel = is_first_output_pair and 1 or 3
            pt.crow_note_on_data(note, note_channel, note_channel+1)
        elseif msg.type == "note_off" then
            pt.crow_note_off_data(note, is_first_output_pair and 2 or 4)
        end
    end
    if msg.type == "cc" then
        if (crow_cc_outputs > 1) then
            local is_selection_a = msg.cc == crow_cc_selection_a
            local is_selection_b = msg.cc == crow_cc_selection_b
            
            if is_selection_a or is_selection_b then
                local crow_output = crow_cc_outputs == 2 and 1 or 3
                if is_selection_a then
                    pt.crow_cc_data(msg, crow_output) 
                end
                if is_selection_b then
                   pt.crow_cc_data(msg, crow_output+1) 
                end
            end
        end
    end
end

pt.handle_clock_data = function(msg, target)
    if msg.type == "clock" then
        target:clock()
    elseif msg.type == "start" then
        target:start()
    elseif msg.type == "stop" then
        target:stop()
    elseif msg.type == "continue" then
        target:continue()
    end
end

pt.handle_cc_limit = function()
  for target, v in pairs(cc_limit_init) do
    for out_ch, ccs in pairs(v) do
      for cc, value in pairs(ccs) do
        target:cc(cc, value, out_ch)
      end
    end
  end

  cc_limit_count = {}
  cc_limit_init = {}
end

pt.device_event = function(origin, device_target, input_channel, output_channel, send_clock, quantize_midi, current_scale, cc_limit, crow_notes, crow_cc_outputs, crow_cc_selection_a, crow_cc_selection_b, data)
    if #data == 0 then
        print("no data")
        return
    end
    
    local msg = midi.to_msg(data)

    local connections = pt.port_connections[origin] -- check this out to debug

    local in_chan = utils.get_midi_channel_value(input_channel, msg.ch)
    local out_ch = utils.get_midi_channel_value(output_channel, msg.ch)
    -- get scale stored in scales object
    local scale = pt.scales[origin]

    --OPTIMISE THIS
    if msg and msg.ch == in_chan and msg.type ~= "clock" then

        
        for k, v in pairs(connections) do
          pt.handle_midi_data(msg, v, out_ch, quantize_midi, scale, cc_limit)
        end
    end
    
    if send_clock then
        for k, v in pairs(connections) do
          pt.handle_clock_data(msg, v)
        end
    end
    -- UNTIL HERE

    if crow_notes > 1 or crow_cc_outputs > 1 then
        pt.process_data_for_crow(msg, crow_notes, crow_cc_outputs, crow_cc_selection_a, crow_cc_selection_b, quantize_midi, scale)
    end

end

pt.user_event = function(id, data) end

return pt