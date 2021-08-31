local MusicUtil = require "musicutil"
local pt_core = {}

pt_core.midi_panic_active = false
pt_core.input_channels = {"No change"}
pt_core.output_channels = {"Device src."}
pt_core.toggles = {"no", "yes"}
pt_core.midi_ports = {}
pt_core.midi_connections = {}
pt_core.available_targets = {}
pt_core.scales = {}
local active_notes = {}

for i = 1, 16 do
    table.insert(pt_core.input_channels, i)
    table.insert(pt_core.output_channels, i)
end

pt_core.scale_names = {}
for i = 1, #MusicUtil.SCALES do
    table.insert(pt_core.scale_names, string.lower(MusicUtil.SCALES[i].name))
end

pt_core.build_scale = function(root, scale, index)
    pt_core.scales[index] = MusicUtil.generate_scale_of_length(root, scale, 128)
end

pt_core.setup_midi = function()
    local midi_ports={}
    local midi_connections = {}
    local available_targets = {"all"}
    for _,dev in pairs(midi.devices) do
        if dev.port~=nil then
          table.insert(midi_ports,dev.name)
           local conn=midi.connect(dev.port)
          table.insert(midi_connections, conn)
        end
    end

    pt_core.midi_ports = midi_ports
    pt_core.midi_connections = midi_connections
    for i = 1, tab.count(midi_ports) do
        table.insert(available_targets, i)
    end
    pt_core.available_targets = available_targets
end

pt_core.remove_active_note = function(target, note, ch)
    local i = 1
    while i <= #active_notes do
        if active_notes[i][1] == target and active_notes[i][2] == note and active_notes[i][3] == ch then
            table.remove(active_notes, i)
        end
        i = i+1
    end
end

pt_core.stop_clocks = function(origin, device_target)
    target_all = device_target == 1

    if target_all then
        for target = 1, #pt_core.midi_ports do
            if origin ~= target then
                pt_core.handle_clock_data({type= "stop"}, pt_core.midi_connections[target])
            end
        end
    elseif origin ~= device_target then
            pt_core.handle_clock_data(msg, pt_core.midi_connections[device_target -1])
    end
end

pt_core.stop_all_notes = function()
    if #active_notes then
        for i=1, #active_notes do
            active_notes[i][1]:note_off(active_notes[i][2], 0, active_notes[i][3])
        end
    end
    active_notes= {}
end

pt_core.handle_midi_data = function(msg, target, out_ch, quantize_midi, current_scale)
    local note = msg.note

    if note ~= nil then
        if quantize_midi then
            note = MusicUtil.snap_note_to_array(note, current_scale)
        end
    end

    if msg.type == "note_off" then
        target:note_off(note, 0, out_ch)
        pt_core.remove_active_note(target, note, out_ch)
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

pt_core.handle_clock_data = function(msg, target)
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

pt_core.device_event = function(origin, device_target, device_channel, interface_channel, send_clock, quantize_midi, current_scale, data)
    if #data == 0 then
        print('no data')
        return
    end
    local msg = midi.to_msg(data)
    local dev_channel_param = device_channel
    local dev_chan = dev_channel_param > 1 and (dev_channel_param - 1) or msg.ch

    local out_ch_param = interface_channel
    local out_ch = out_ch_param > 1 and (out_ch_param - 1) or msg.ch

    -- should data target all ports
    local target_all = device_target == 1 

    if msg and msg.ch == dev_chan then
        -- get scale stored in scales object
        local scale = pt_core.scales[origin]
        if target_all then
            for target = 1, #pt_core.midi_ports do
                if origin ~= target then
                    pt_core.handle_midi_data(msg, pt_core.midi_connections[target], out_ch, quantize_midi, scale)
                end
            end
        elseif origin ~= device_target then
            pt_core.handle_midi_data(msg, pt_core.midi_connections[device_target - 1], out_ch, quantize_midi, scale)
        end
    end

    if send_clock then
        if target_all then
            for target = 1, #pt_core.midi_ports do
                if origin ~= target then
                    pt_core.handle_clock_data(msg, pt_core.midi_connections[target])
                end
            end
        elseif origin ~= device_target then
                pt_core.handle_clock_data(msg, pt_core.midi_connections[device_target -1])
        end
    end
end

pt_core.root_note_formatter = function(value)
  return MusicUtil.note_num_to_name(value)
end

pt_core.user_device_event = function(data)
  print('>> user-device-event <<')
end

pt_core.user_interface_event = function(data)
  print('>> user-interface-event <<')
end

return pt_core