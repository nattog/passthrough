local Passthrough = require 'passthrough/lib/mod'

function midi_event(data, origin)
    local msg = midi.to_msg(data)
    print(origin.port .. ' ' .. origin.name .. ' ' .. msg.type)
end

function init()
    Passthrough.user_event = midi_event
end

function redraw()
end
