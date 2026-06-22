# Wazak

Tiny macOS floating companion MVP.

## Run

```sh
swift run Wazak
```

## MVP Behavior

- Shows one Malangi character with a badge below it.
- Hovering reveals left/right arrows.
- Arrows switch to previous/next Malangi.
- Clicking the Malangi plays its sound.

## Replacing Placeholder Assets

The current build draws sample Malangis and generates short tones in code.
To wire real assets, add images or sounds under:

```txt
Sources/Wazak/Resources/
```

Then set `imageName` or `soundName` in `Sources/Wazak/main.swift`.
