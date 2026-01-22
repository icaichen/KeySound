# Keyboard Sound Simulator

A macOS app that simulates mechanical keyboard sounds when typing, similar to Tickeys.

## Setup

1. Download open source sound files from the sources below.
2. Rename them to key_click1.wav, key_click2.wav, key_click3.wav and place in the project root or Resources.
3. Build and run: `cd KeyboardSoundSimulator && swift build`

## Sound Sources

- [Mechvibes Soundpacks](https://mechvibes.com/soundpacks) - Free community-made soundpacks for mechanical keyboards.
- [Pixabay Mechanical Keyboard Sounds](https://pixabay.com/sound-effects/search/mechanical-keyboard/) - Free sound effects.
- [Tickeys GitHub](https://github.com/yingDev/Tickeys) - Original Tickeys project (sounds may be in binary).
- [KeyEcho](https://github.com/ZacharyL2/KeyEcho) - Another open source keyboard sound app.
- [KeyboardSounds](https://github.com/nathan-fiscaletti/keyboardsounds) - Includes 16 built-in profiles.

## Usage

- The app runs in the status bar.
- Click the icon to toggle sound on/off.
- When enabled, key presses will play sounds.

## Permissions

Requires Accessibility permissions for global keyboard monitoring.