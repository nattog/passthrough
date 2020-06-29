# Passthrough
Norns library for passing midi between devices.

## Intro

Initially conceived as an easy way to pass midi information from the keystep controller to other devices, whilst running unrelated scripts. Passthrough allowing norns users to pass midi between devices with optional clocking from interface to device and quantizing of note info sent the other way.

## How to use

Include passthrough at the top of your script
`local Passthrough = include("lib/passthrough")`

and then add `Passthrough.init()` to your `init` function.

```lua
function init()
    Passthrough.init()
end
```

User event callbacks can also be added for specific routing.

```lua
function midi_device_event(data)
  -- your code
end

function init()
    Passthrough.init()
    Passthrough.user_device_event = midi_device_event
end
```

Find Passthrough related parameters in the `Passthrough` group in the params menu.

![paramsmenu](img/params1.png)
![paramsmenu2](img/params2.png)

## Contributing

PRs welcome
