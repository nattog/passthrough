# Passthrough
Norns library for passing midi between devices.

## Intro

Initially conceived as an easy way to pass midi information from the keystep controller to other devices, whilst running unrelated scripts. Passthrough allowing norns users to pass midi between devices with optional clocking from interface to device and quantizing of note info sent the other way.

## How to use

Include passthrough at the top of your script
`local Passthrough = include("lib/Passthrough")`

and then add `Passthrough.init()` to your `init` function.

Find Passthrough related parameters in the `Passthrough` group in the params menu.

## Contributing

PRs welcome