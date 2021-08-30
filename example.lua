local Passthrough = include("lib/passthrough")

local function device_event()
  print('user-device-event')
end

local function interface_event()
  print('user-interface-event')
end

function init()
    Passthrough.init()
    Passthrough.user_interface_event = interface_event
    Passthrough.user_device_event = device_event
end

function redraw()
end

function rerun() 
    norns.script.load(norns.state.script)
end