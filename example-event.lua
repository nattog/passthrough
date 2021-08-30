local Passthrough = require 'passthrough/lib/mod'

function midi_device_event(data)
    local msg = midi.to_msg(data)
    print("device")
    tab.print(msg)
end

function midi_interface_event(data)
    local msg = midi.to_msg(data)
    print("interface")
    tab.print(msg)
end

function init()
    Passthrough.user_device_event = midi_device_event
    Passthrough.user_interface_event = midi_interface_event
end

function redraw()
end
