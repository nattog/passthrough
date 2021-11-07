local MusicUtil = require "musicutil"
local pt = {}
local utils = require("passthrough/lib/utils")

pt.midi_panic_active = false
pt.input_channels = {"No change"}
pt.output_channels = {"Device src."}
pt.toggles = {"no", "yes"}
pt.available_targets = {}
pt.scales = {}
local active_notes = {}

-- TODO: this is a mess and needs refactoring
pt.midi_ports = {}
pt.midi_connections = {}
pt.port_connections = {}
id_port_lookup = {}
pt.ports = {}
pt.targets = {}

pt.origin_event = function (id, data) end

-- CORE NORNS OVERRIDES --
local midi_event = _norns.midi.event

_norns.midi.event = function(id, data)
  midi_event(id, data)
  pt.origin_event(id, data) -- passthrough
end

-- UTIL --
local function get_midi_channel_value(channel_param_value, msg_channel)
    local channel_param = channel_param_value
    return channel_param > 1 and (channel_param - 1) or msg_channel
end

-- SCALE SETUP --
pt.scale_names = {}
for i = 1, #MusicUtil.SCALES do
    table.insert(pt.scale_names, string.lower(MusicUtil.SCALES[i].name))
end

pt.build_scale = function(root, scale, index)
    pt.scales[index] = MusicUtil.generate_scale_of_length(root, scale, 128)
end

-- MIDI DEVICE DETECTION --
for i = 1, 16 do
    table.insert(pt.input_channels, i)
    table.insert(pt.output_channels, i)
end

pt.get_port_from_id = function(id) return id_port_lookup[id] end

pt.get_target_connections = function(origin, selection) 
  local t = {}

  -- SELECT ALL PORTS
  if selection == 1 then
    for k, v in pairs(pt.midi_connections) do
      if v.port ~= origin then
        table.insert(t, v.connect)  
      end
    end

    return t
  else
    -- SINGLE PORT - still create iterable for ease
    local port_target = pt.targets[origin][selection]
    if origin ~= port_target then
      local mc = utils.table_find_value(pt.midi_connections, function(k, v) return v.port == port_target end)
      if mc then table.insert(t, mc.connect) end
    end
  end
  
  return t
end

create_port_targets_table = function(port)
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
    local midi_connections = {}
    local targets = {}
    local available_targets = {"all"}

    for _,dev in pairs(midi.devices) do
        if dev.port~=nil then
            id_port_map[dev.id] = dev.port
            ports[dev.port] = {id=dev.id, name=dev.name, port=dev.port, connect=midi.connect(dev.port)}
            
            table.insert(midi_ports, {name=dev.name, port=dev.port})
            table.insert(midi_connections, {connect= midi.connect(dev.port), port=dev.port})
            local port_targets = create_port_targets_table(dev.port)
            targets[dev.port] = port_targets
        end
    end

    table.sort(midi_connections, function(a, b) return a.port < b.port end)
    table.sort(midi_ports, function(a, b) return a.port < b.port end)

    pt.ports = ports
    pt.midi_ports = midi_ports
    pt.midi_connections = midi_connections
    id_port_lookup = id_port_map

    for i = 1, tab.count(midi_ports) do
        table.insert(available_targets, i)
    end
    pt.available_targets = available_targets
    pt.targets = targets
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

-- DATA HANDLERS --
pt.handle_midi_data = function(msg, target, out_ch, quantize_midi, current_scale)
    local note = msg.note

    if note ~= nil then
        if quantize_midi == 2 then
            note = MusicUtil.snap_note_to_array(note, current_scale)
        end
    end

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
        target:cc(msg.cc, msg.val, out_ch)
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

pt.device_event = function(origin, device_target, input_channel, output_channel, send_clock, quantize_midi, current_scale, data)
    if #data == 0 then
        print("no data")
        return
    end
    
    local msg = midi.to_msg(data)

    local connections = pt.port_connections[origin] -- check this out to debug

    local in_chan = get_midi_channel_value(input_channel, msg.ch)
    local out_ch = get_midi_channel_value(output_channel, msg.ch)

    --OPTIMISE THIS
    if msg and msg.ch == in_chan and msg.type ~= "clock" then
        -- get scale stored in scales object
        local scale = pt.scales[origin]
        
        for k, v in pairs(connections) do
          pt.handle_midi_data(msg, v, out_ch, quantize_midi, scale)
        end
    end
    
    if send_clock then
        for k, v in pairs(connections) do
          pt.handle_clock_data(msg, v)
        end
    end
    -- UNTIL HERE
end

pt.user_event = function(id, data) end

return pt