-- passthrough
--
-- library for passing midi
-- from device to an interface
-- + clock/cc from interface
-- + scale quantizing
-- + user event callbacks
--
-- for how to use see example
--
-- PRs welcome

local Passthrough = {}
local tab = require "tabutil"
local core = require("passthrough/lib/core")
local devices = {}
local midi_device
local midi_interface
local clock_device
local quantize_midi
local current_scale = {}

function Passthrough.user_device_event(data)
end

function Passthrough.user_interface_event(data)
end

function device_event(data)
    core.device_event(midi_interface, params:get("device_channel"), params:get("interface_channel"), quantize_midi, current_scale, data)
    Passthrough.user_device_event(data)
end

function interface_event(data)
    core.interface_event(midi_device, params:get("device_channel"), params:get("clock_device"), params:get("cc_direction"), data)
    Passthrough.user_interface_event(data)
end

function build_scale()
    current_scale = core.build_scale(params:get("root_note"), params:get("scale_mode"))
end

function Passthrough.init()
    clock_device = false
    quantize_midi = false

    midi_device = midi.connect(1)
    midi_device.event = device_event
    midi_interface = midi.connect(2)
    midi_interface.event = interface_event

    devices = core.get_midi_devices()

    params:add_group("PASSTHROUGH", 9)
    params:add {
        type = "option",
        id = "midi_device",
        name = "Device",
        options = devices,
        default = 1,
        action = function(value)
            midi_device.event = nil
            midi_device = midi.connect(value)
            midi_device.event = device_event
        end
    }

    params:add {
        type = "option",
        id = "midi_interface",
        name = "Interface",
        options = devices,
        default = 2,
        action = function(value)
            midi_interface.event = nil
            midi_interface = midi.connect(value)
            midi_interface.event = interface_event
        end
    }

    params:add {
        type = "option",
        id = "cc_direction",
        name = "CC msg direction",
        options = core.cc_directions,
        default = 1
    }

    params:add {
        type = "option",
        id = "device_channel",
        name = "Device channel",
        options = core.device_channels,
        default = 1
    }

    params:add {
        type = "option",
        id = "interface_channel",
        name = "Interface channel",
        options = core.interface_channels,
        default = 1
    }

    params:add {
        type = "option",
        id = "clock_device",
        name = "Clock device",
        options = core.toggles,
        action = function(value)
            clock_device = value == 2
            if value == 1 then
                midi_device:stop()
            end
        end
    }

    params:add {
        type = "option",
        id = "quantize_midi",
        name = "Quantize",
        options = core.toggles,
        action = function(value)
            quantize_midi = value == 2
            build_scale()
        end
    }

    params:add {
        type = "option",
        id = "scale_mode",
        name = "Scale",
        options = core.scale_names,
        default = 5,
        action = build_scale
    }

    params:add {
        type = "number",
        id = "root_note",
        name = "Root",
        min = 0,
        max = 11,
        default = 0,
        formatter = function(param) 
        return core.root_note_formatter(param:get())
        end,
        action = build_scale
    }

    -- expose device and interface connections
    Passthrough.device = midi_device
    Passthrough.interface = midi_interface
end

return Passthrough
