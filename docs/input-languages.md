# Input languages

The right-hand button shows the active language. English uses a neutral globe;
Bulgarian and Vietnamese use flag emoji. Dropdown rows show English, Български
and Tiếng Việt, with tooltips and accessible names:

- 🇧🇬 chooses Bulgarian phonetic and stops Vietnamese input.
- 🇻🇳 explicitly starts Vietnamese Telex. The popup closes immediately and a
  spinner overlays the flag while input starts. After startup, the initiating
  bar briefly takes and releases keyboard focus so the application reattaches
  its Wayland text input; the spinner remains visible through this handoff.
- **English** chooses English and keeps the current secondary language.

A checkmark identifies the secondary language, independently of the active
language. Alt+Shift switches within the selected English/Bulgarian or
English/Vietnamese pair. Selection is global across applications; XKB maintains
its active layout per keyboard. Layout events follow the keyboard that changed,
including a laptop keyboard when an external keyboard is the main device.

## Optional input provider

English/Bulgarian and the indicator work with the bundled XKB fallback.
Vietnamese requires an explicitly configured provider. The shell does not
install, configure or start an input daemon on load. External system
provisioning owns input packages, toolkit environment, startup policy and
service configuration.

Configure `$XDG_CONFIG_HOME/zephyrus-shell/input-language.json` with a command
argument array. See [the example](../config/input-language.example.json):

```json
{"command":["/path/to/your/input-controller"]}
```

Arguments are passed directly, without a shell. The provider receives:

- `status [keyboard]`: report state without starting any services. The optional
  keyboard name identifies the device from the latest compositor layout event.
- `select en|bg|vi`: select a language, handling any explicit startup, stop or
  configuration needed for the chosen pair, then report the resulting state.

Both actions return a single JSON object:

```json
{"available":true,"secondary":"vi","language":"en","running":true}
```

`available` means Vietnamese can be selected. `secondary` is `bg` or `vi`, and
`language` is `en`, `bg` or `vi`. `running` reports the provider's input service
state. An optional `error` supplies a user-facing explanation; unsuccessful
requests must exit nonzero. The provider owns Alt+Shift and the selected pair's
lifecycle. It must not restore a previous login's Vietnamese selection.
Vietnamese is hidden when no provider is configured, its executable is absent,
or it reports `available:false`. There is no preliminary service launch when a
provider handles selection. Changing the provider file takes effect on the next
request, including after a shell reload.

## Layout overrides

The bundled Hyprland policy defaults to English/Bulgarian phonetic and Alt+Shift.
Optional user defaults live in
`$XDG_CONFIG_HOME/zephyrus-shell/input-method.lua`.
Providers can publish a current-session Lua layout override at
`$XDG_RUNTIME_DIR/zephyrus-shell/input-language-INSTANCE.lua`, where `INSTANCE`
is `HYPRLAND_INSTANCE_SIGNATURE` with characters outside `[a-zA-Z0-9_.-]`
replaced by underscores. It is loaded after the user defaults, so compositor
reloads preserve the explicitly selected pair while new logins use defaults.
The shell reads only this public override; provider state files remain private.

A narrow keyboard-policy reload does not need logout:

```sh
hyprctl eval 'dofile("/path/to/zephyrus-shell/hyprland/input-method.lua")'
```

Toolkit environment changes can require relaunching the affected application
or a new login. Proprietary and sandboxed clients still need a real typing check.

## Checks

Run `bash scripts/check-language.sh` for the production button, popup, singleton
and configured-provider/fallback paths. It checks queued requests, layout events,
immediate menu dismissal, the spinner and the post-start focus handoff using
isolated state and a private bus. Python tests cover provider argument handling
and session layout override ordering. These checks do not change the current
desktop's layouts or services.

A live Hyprland check on 2026-10-04 used native Wayland Firefox and Zed scratch
instances. Zed reproduced the first-click failure despite UniKey reporting
active. After the focus handoff, the first selection produced `tiếng Việt` in
two consecutive Bulgarian/Vietnamese cycles in both applications. Left Alt+Shift
switched English/Telex and the indicator followed both changes in Firefox.
