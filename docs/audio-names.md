# Know which device you are controlling

Sound output and microphone each show their current device name, level and mute
state. The selectors contain currently exposed PipeWire devices, not a hardcoded
list. Hardware with an unavailable active port is marked unavailable. A missing
microphone is reported as unavailable, rather than as an enabled microphone.

If the active sound-card profile exposes only an output, and an available profile
adds a microphone while preserving that output mode, an **Enable microphone
alongside speakers** action appears. It changes profiles only when clicked and
rejects the change if the hardware configuration has changed since it was read.

Each file in `config/audio/*.json` contains independent naming rules. Files are
read alphabetically; the first matching rule wins. Add a file for each monitor,
dock, headset or machine. Open **Device identifiers & naming** for the current
node and port identities. Use **Reload names** after editing.

```json
[
  {
    "contains": {"node.description": "DELL S2722DC"},
    "label": "Dell speakers",
    "role": "speaker"
  }
]
```

`match` requires exact string equality; `contains` requires a substring. All
specified fields must match. Fields include PipeWire/PulseAudio properties plus
`node.name`, `node.description`, `port.name`, and `port.description`. Avoid numeric
runtime IDs or card indices: they change across restarts. A connector identity
alone identifies a connection path, not the monitor attached to it.

The supplied laptop file distinguishes the speaker and headphone ports. The Dell
file requires the display's advertised identity, so another monitor on that same
connector gets its own reported name. Multiple identical monitor models may need
an additional stable serial or connector field to distinguish them.

Aliases only rename controls. They do not force profiles, choose a device, or
change routing when hardware is plugged in. Device selection changes the default
output/input through WirePlumber. Applications with an explicitly assigned device
may retain their own routing. The sliders control the named device, not every
application's individual volume.

Route metadata is read using `pactl`; changes are subscribed to only while the
audio controls exist. No new background audio daemon is installed.

Optional `role` values are `speaker`, `headphones`, `microphone`, `headset`, and
`hdmi`. Roles choose device icons; PipeWire source/sink type determines which
selector lists the device. Existing rules without roles remain supported.
