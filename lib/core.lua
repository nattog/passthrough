local MusicUtil = require "musicutil"
local pt_core = {}

pt_core.params_added = false
pt_core.device_channels = {"No change"}
pt_core.interface_channels = {"Device src."}
pt_core.midi_ports = {}
pt_core.midi_connections = {}
pt_core.available_targets = {"all"}

pt_core.raw_ports = {}

for i = 1, 16 do
    table.insert(pt_core.raw_ports, i)
    table.insert(pt_core.device_channels, i)
    table.insert(pt_core.interface_channels, i)
    table.insert(pt_core.available_targets, i)
end

pt_core.scale_names = {}
for i = 1, #MusicUtil.SCALES do
    table.insert(pt_core.scale_names, string.lower(MusicUtil.SCALES[i].name))
end

pt_core.cc_directions = {"D --> I", "D <--> I"}
pt_core.toggles = {"no", "yes"}

pt_core.build_scale = function(root, scale)
    return MusicUtil.generate_scale_of_length(root, scale, 128)
end

pt_core.get_midi_devices = function()
    d = {}
    for id, device in pairs(midi.vports) do
        d[id] = device.name
    end
    return d
end

pt_core.setup_midi = function()
    local midi_ports={}
    local midi_connections = {}
    for _,dev in pairs(midi.devices) do
        if dev.port~=nil then
          table.insert(midi_ports,dev.name)
          local existing_event = midi.vports[dev.id].event and midi.vports[dev.id].event or nil
          local conn=midi.connect(dev.port)
          conn.event=function(data)
            if existing_event then
                existing_event(data)
            end
              device_event(data)
          end
          table.insert(midi_connections, conn)
        end
      end

    pt_core.midi_ports = midi_ports
    pt_core.midi_connections = midi_connections
    tab.print(midi_ports)
    tab.print(midi_connections)
end

pt_core.handle_midi_data = function(msg, target, out_ch, quantize_midi, current_scale)
    local note = msg.note

    if msg.note ~= nil then
        if quantize_midi then
            note = MusicUtil.snap_note_to_array(note, current_scale)
        end
    end

    if msg.type == "note_off" then
        target:note_off(note, 0, out_ch)
    elseif msg.type == "note_on" then
        target:note_on(note, msg.vel, out_ch)
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

pt_core.device_event = function(origin, device_target, device_channel, interface_channel, quantize_midi, current_scale, data)
    if #data == 0 then
          print('no data')
          return
    end
    local msg = midi.to_msg(data)
    local dev_channel_param = device_channel
    local dev_chan = dev_channel_param > 1 and (dev_channel_param - 1) or msg.ch

    local out_ch_param = interface_channel
    local out_ch = out_ch_param > 1 and (out_ch_param - 1) or msg.ch

    if msg and msg.ch == dev_chan then
        if device_target == 1 then
            for target = 1, #pt_core.midi_ports do
                if origin ~= target then
                    pt_core.handle_midi_data(msg, pt_core.midi_connections[target], out_ch, quantize_midi, current_scale)
                end
            end
        else
            if origin ~= target then
                pt_core.handle_midi_data(msg, pt_core.midi_connections[device_target - 1], out_ch, quantize_midi, current_scale)
            end
        end
    end
end


pt_core.interface_event = function(midi_device, device_channel, clock_device, cc_direction, data)
    local msg = midi.to_msg(data)
    local note = msg.note
  
    if clock_device then
        if msg.type == "clock" then
            midi_device:clock()
        elseif msg.type == "start" then
            midi_device:start()
        elseif msg.type == "stop" then
            midi_device:stop()
        elseif msg.type == "continue" then
            midi_device:continue()
        end
    end
    if cc_direction == 2 then
        local dev_channel_param = device_channel
        local dev_chan = dev_channel_param > 1 and (dev_channel_param - 1) or msg.ch
  
        if msg.type == "cc" then
            midi_device:cc(msg.cc, msg.val, dev_chan)
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