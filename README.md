# Brightness Overclock

A macOS menu bar app for pushing the built-in Liquid Retina XDR display past normal SDR brightness.

It lets SDR content use the XDR range: roughly **1,000 nits → 1,600 nits**.

_Note: this project is vibe-coded._

## Features

- Menu bar toggle for brightness overclocking.
- Brightness-key support past native maximum brightness.
- 8 boost steps through the XDR range.
- Remembers your last boost level.
- Configurable battery rules for allowing or disabling boost on battery power.
- Launch-at-login support.

For implementation details, see [Contributing](CONTRIBUTING.md).

## Build and install

```sh
make install
```

This will:

1. Build the app.
2. Sign it.
3. Copy it to `/Applications`.
4. Launch it.

## Signing note

The Makefile uses your first available **Apple Development** signing identity.

If no Apple Development identity is found, the app is ad-hoc signed. It will still run, but macOS may revoke the Accessibility permission after each rebuild.

To avoid that, sign into Xcode once with any Apple ID so an Apple Development certificate is available.

## Usage

### Toggle boost

Open the menu bar sun icon and toggle:

```text
Overclock brightness
```

> First use goes to the maximum detected boost level. After that, toggling on restores your last boost level.

### Brightness keys

The brightness keys work like this:

- **Brightness Up / F2**: once native brightness is maxed, keeps stepping into the XDR range.
- **Brightness Down / F1**: steps back down through the boost range before returning to native brightness.

There are 8 boost steps.

### Accessibility permission

Brightness-key control requires Accessibility permission.

In the app menu:

```text
Enable brightness keys…
```

Then grant permission in System Settings and relaunch the app if needed.

> The menu toggle works even if Accessibility permission is not granted.

### Battery rules

Use the **Boost on battery** menu to choose:

- Always allow boost on battery. This is the default, preserving the original behavior.
- Turn off boost below a chosen battery percentage. The default threshold is 30%, and the menu offers 10% increments from 10% to 100%.
- Don’t allow boost while on battery.

When boost is blocked by battery policy, the app turns boost off and prevents re-enabling it until the policy allows it again. If boost was on when the policy blocked it, it automatically restores that boost level when allowed again. The setting is persisted between launches.

### Launch at login

Use the menu item:

```text
Launch at login
```

This is enabled automatically on first launch. You can turn it off from the menu.

## Known limitations

- Built-in XDR display only.
- The nits value shown in the menu is an estimate, not a measurement.
- High boost can cause slight color drift because gamma scaling is not colorimetric.
- Native brightness is read through Apple's private DisplayServices framework, so a macOS update could break brightness-key interception.
- Sustained high brightness uses more power and can heat the panel. macOS may dim the display under thermal load.

