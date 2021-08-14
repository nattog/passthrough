--
-- require the `mods` module to gain access to hooks, menu, and other utility
-- functions.
--

local mod = require 'core/mods'

--
-- [optional] a mod is like any normal lua module. local variables can be used
-- to hold any state which needs to be accessible across hooks, the menu, and
-- any api provided by the mod itself.
--
-- here a single table is used to hold some x/y values
--

local state = {
  midi_device = 1,
  device_channel=1,
  midi_interface = 2,
  interface_channel=1,
  clock_device = 1,
  quantize_midi = 1,
  current_scale = 1,
  cc_direction = 1,
  root_note = 0
}

local Passthrough = {}
tab = require "tabutil"
MusicUtil = require "musicutil"
local first_init = false
local devices = {}
local midi_device
local midi_interface
local clock_device
local quantize_midi
local scale_names = {}
local current_scale = {}
local midi_notes = {}
local cc_directions = {"D --> I", "D <--> I"}

local device_channels = {"No change"}
local interface_channels = {"Device src."}

for i = 1, 16 do
    table.insert(device_channels, i)
    table.insert(interface_channels, i)
end

for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
end


function Passthrough.user_device_event(data)
end

function Passthrough.user_interface_event(data)
end

function Passthrough.device_event(data)
    if #data == 0 then
        return
    end
    local msg = midi.to_msg(data)
    local dev_channel_param = state.device_channel
    local dev_chan = dev_channel_param > 1 and (dev_channel_param - 1) or msg.ch

    local out_ch_param = state.interface_channel
    local out_ch = out_ch_param > 1 and (out_ch_param - 1) or msg.ch

    if msg and msg.ch == dev_chan then
        local note = msg.note

        if msg.note ~= nil then
            if state.quantize_midi == true then
                note = MusicUtil.snap_note_to_array(note, state.current_scale)
            end
        end

        if msg.type == "note_off" then
            midi_interface:note_off(note, 0, out_ch)
        elseif msg.type == "note_on" then
            midi_interface:note_on(note, msg.vel, out_ch)
        elseif msg.type == "key_pressure" then
            midi_interface:key_pressure(note, msg.val, out_ch)
        elseif msg.type == "channel_pressure" then
            midi_interface:channel_pressure(msg.val, out_ch)
        elseif msg.type == "pitchbend" then
            midi_interface:pitchbend(msg.val, out_ch)
        elseif msg.type == "program_change" then
            midi_interface:program_change(msg.val, out_ch)
        elseif msg.type == "cc" then
            midi_interface:cc(msg.cc, msg.val, out_ch)
        end
    end

    Passthrough.user_device_event(data)
end

function Passthrough.interface_event(data)
    local msg = midi.to_msg(data)
    local note = msg.note

    if state.clock_device then
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
    if state.cc_direction == 2 then
        local dev_channel_param = state.device_channel
        local dev_chan = dev_channel_param > 1 and (dev_channel_param - 1) or msg.ch

        if msg.type == "cc" then
            midi_device:cc(msg.cc, msg.val, dev_chan)
        end
    end

    Passthrough.user_interface_event(data)
end

function Passthrough.build_scale()
    current_scale = MusicUtil.generate_scale_of_length(state.root_note, state.current_scale, 128)
end

function Passthrough.get_midi_devices()
    d = {}
    for id, device in pairs(midi.vports) do
        d[id] = device.name
    end
    return d
end

function get_midi_devices()
    d = {}
    for id, device in pairs(midi.vports) do
        d[id] = device.name
    end
    return d
end

function Passthrough.init()
    -- params:add_group("PASSTHROUGH", 9)
    -- params:add {
    --     type = "option",
    --     id = "midi_device",
    --     name = "Device",
    --     options = devices,
    --     default = 1,
    --     action = function(value)
    --         midi_device.event = nil
    --         midi_device = midi.connect(value)
    --         midi_device.event = Passthrough.device_event
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "midi_interface",
    --     name = "Interface",
    --     options = devices,
    --     default = 2,
    --     action = function(value)
    --         midi_interface.event = nil
    --         midi_interface = midi.connect(value)
    --         midi_interface.event = Passthrough.interface_event
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "cc_direction",
    --     name = "CC msg direction",
    --     options = cc_directions,
    --     default = 1
    -- }

    -- local channels = {"No change"}
    -- for i = 1, 16 do
    --     table.insert(channels, i)
    -- end
    -- params:add {
    --     type = "option",
    --     id = "device_channel",
    --     name = "Device channel",
    --     options = channels,
    --     default = 1
    -- }

    -- channels[1] = "Device src."
    -- params:add {
    --     type = "option",
    --     id = "interface_channel",
    --     name = "Interface channel",
    --     options = channels,
    --     default = 1
    -- }

    -- params:add {
    --     type = "option",
    --     id = "clock_device",
    --     name = "Clock device",
    --     options = {"no", "yes"},
    --     action = function(value)
    --         clock_device = value == 2
    --         if value == 1 then
    --             midi_device:stop()
    --         end
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "quantize_midi",
    --     name = "Quantize",
    --     options = {"no", "yes"},
    --     action = function(value)
    --         quantize_midi = value == 2
    --         Passthrough.build_scale()
    --     end
    -- }

    -- params:add {
    --     type = "option",
    --     id = "scale_mode",
    --     name = "Scale",
    --     options = scale_names,
    --     default = 5,
    --     action = function()
    --         Passthrough.build_scale()
    --     end
    -- }

    -- params:add {
    --     type = "number",
    --     id = "root_note",
    --     name = "Root",
    --     min = 0,
    --     max = 11,
    --     default = 0,
    --     formatter = function(param)
    --         return MusicUtil.note_num_to_name(param:get())
    --     end,
    --     action = function()
    --         Passthrough.build_scale()
    --     end
    -- }

    -- expose device and interface connections
    Passthrough.device = midi_device
    Passthrough.interface = midi_interface
    
end

--
-- [optional] hooks are essentially callbacks which can be used by multiple mods
-- at the same time. each function registered with a hook must also include a
-- name. registering a new function with the name of an existing function will
-- replace the existing function. using descriptive names (which include the
-- name of the mod itself) can help debugging because the name of a callback
-- function will be printed out by matron (making it visible in maiden) before
-- the callback function is called.
--
-- here we have dummy functionality to help confirm things are getting called
-- and test out access to mod level state via mod supplied fuctions.
--

mod.hook.register("system_post_startup", "passthrough", function()
  -- state.system_post_startup = true
  -- tab.print(midi.vports)


  
  -- grab state here
end)

mod.hook.register("script_pre_init", "passthrough", function()
  -- tweak global environment here ahead of the script `init()` function being called
  if not first_init then
    devices = get_midi_devices()
    midi_device = midi.connect(state.midi_device)
    midi_interface = midi.connect(state.midi_interface)
    passthrough_config = generate_param_config()
    first_init = true
  end
  Passthrough.init()
  midi_device.event = Passthrough.device_event
  midi_interface.event = Passthrough.interface_event
    
end)


--
-- [optional] menu: extending the menu system is done by creating a table with
-- all the required menu functions defined.
--

local m = {}


generate_param_config = function() 
  return {
  midi_device = {
    param_type = "option",
    id = "midi_device",
    name = "Midi Device",
    options = devices,
    action = function(value)
        midi_device.event = nil
        midi_device = midi.connect(value)
        midi_device.event = Passthrough.device_event
    end
  },
  midi_interface = {
    param_type = "option",
    id = "midi_interface",
    name = "Midi Interface",
    options = devices,
    action = function(value)
        midi_interface.event = nil
        midi_interface = midi.connect(value)
        midi_interface.event = Passthrough.interface_event
    end
  },
  device_channel = {
    param_type = "option",
    id = "device_channel",
    name = "Device channel",
    options = device_channels
  },
  interface_channel = {
    param_type = "option",
    id = "interface_channel",
    name = "Interface channel",
    options = interface_channels
  },
  cc_direction = {    
    param_type = "option",
    id = "cc_direction",
    name = "CC msg direction",
    options = cc_directions
  },
  clock_device = {
    param_type = "option",
    id = "clock_device",
    name = "Clock device",
    options = {"no", "yes"},
    action = function(value)
        clock_device = value == 2
        if value == 1 then
            midi_device:stop()
        end
    end
    },
  quantize_midi = {
    param_type = "option",
    id = "quantize_midi",
    name = 'Quantize midi',
    options = {"no", "yes"},
    action = function(value)
        quantize_midi = value == 2
        Passthrough.build_scale()
    end
  },
  root_note = {
    param_type = 'number',
    id = 'root_note',
    name = "Root note",
    minimum = 0,
    maximum = 11,
    formatter = function(value)
      return MusicUtil.note_num_to_name(state.root_note)
    end,
    action = function()
        Passthrough.build_scale()
    end
  },
  current_scale = {
      param_type = 'option',
      id = 'current_scale',
      name = 'Current scale',
      options = scale_names,
      action = function()
        Passthrough.build_scale()
      end
    }
}
end

local screen_order = {{"midi_device", "midi_interface", "device_channel", "interface_channel", "clock_device", "cc_direction"}, {'quantize_midi', 'root_note', 'current_scale'}}

local screen_delta = 1
local page = 1

function update_parameter(p, dir)
  -- update options
  if p.param_type == "option" then
    state[p.id] = util.clamp(state[p.id] + dir, 1, #p.options)
  end

  -- generate scale
  if p.param_type == 'number' then
    state[p.id] = util.clamp(state[p.id] + dir, p.minimum, p.maximum)
  end
  
  if p.action and type(p.action == 'function') then
    p.action(state[p.id])
  end
  
  tab.print(state)
end

function format_parameter(p) 
  if p.formatter and type(p.formatter == 'function') then
    return p.formatter()
  else
    if p.param_type == "option" then
      return p.options[state[p.id]]
    end
    return state[p.id]
  end
end

m.key = function(n, z)
  if n == 2 and z == 1 then
    -- return to the mod selection menu
    mod.menu.exit()
  end
  if n == 3 and z == 1 then
    page = page == 1 and 2 or 1
    screen_delta = 1
    mod.menu.redraw()
  end
end


m.enc = function(n, d)
  if n == 2 then
    screen_delta = util.clamp(screen_delta + d, 1, #screen_order[page])
  end
  
  if n == 3 then
    local param = passthrough_config[screen_order[page][screen_delta]]
    update_parameter(param, d)
  end 
  mod.menu.redraw()
end


m.redraw = function()
  screen.clear()
  for index, value in ipairs(screen_order[page]) do
    screen.move(4, 10 * index)
    local param = passthrough_config[value]
    screen.level(index == screen_delta and 15 or 7)
    screen.text(param.name .. " " .. format_parameter(param))
  end
  
  screen.update()
end

m.init = function() 
  if not first_init then
    devices = get_midi_devices()
    midi_device = midi.connect(state.midi_device)
    midi_interface = midi.connect(state.midi_interface)
    first_init = true
  end
  passthrough_config = generate_param_config()
  page = 1
  screen_delta = 1
  
end -- on menu entry, ie, if you wanted to start timers

m.deinit = function() end -- on menu exit

-- register the mod menu
--
-- NOTE: `mod.this_name` is a convienence variable which will be set to the name
-- of the mod which is being loaded. in order for the menu to work it must be
-- registered with a name which matches the name of the mod in the dust folder.
--
mod.menu.register(mod.this_name, m)


--
-- [optional] returning a value from the module allows the mod to provide
-- library functionality to scripts via the normal lua `require` function.
--
-- NOTE: it is important for scripts to use `require` to load mod functionality
-- instead of the norns specific `include` function. using `require` ensures
-- that only one copy of the mod is loaded. if a script were to use `include`
-- new copies of the menu, hook functions, and state would be loaded replacing
-- the previous registered functions/menu each time a script was run.
--
-- here we provide a single function which allows a script to get the mod's
-- state table. using this in a script would look like:
--
-- local mod = require 'name_of_mod/lib/mod'
-- local the_state = mod.get_state()
--
return Passthrough
