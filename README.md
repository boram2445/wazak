# Wazak

Tiny macOS floating companion MVP.

## Run

```sh
swift run Wazak
```

With Supabase sync:

```sh
SUPABASE_URL="https://your-project.supabase.co" \
SUPABASE_PUBLISHABLE_KEY="your-publishable-key" \
swift run Wazak
```

If the Supabase variables are not set, Wazak keeps working in local-only mode.

## MVP Behavior

- Shows one Malangi character with a badge below it.
- Hovering reveals left/right arrows.
- Arrows switch to previous/next Malangi.
- Clicking the Malangi plays its sound.
- Registered Malangis are saved locally and synced to Supabase when configured.
- Images and sounds are uploaded to the `malangi-assets` Supabase Storage bucket when sync is configured.

## Replacing Placeholder Assets

The current build draws sample Malangis and generates short tones in code.
To wire real assets, add images or sounds under:

```txt
Sources/Wazak/Resources/
```

Then set `imageName` or `soundName` in `Sources/Wazak/main.swift`.
