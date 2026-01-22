#!/bin/bash

# Ensure directories exist
mkdir -p Sources/Sounds/MX_Blue
mkdir -p Sources/Sounds/Typewriter_New
mkdir -p Sources/Sounds/Opera_GX

# Base path
BASE="temp_assets/keyboardsounds/keyboardsounds/profiles"

# 1. MX Blue (Classic Clicky)
echo "Processing MX Blue..."
# MX Blue has press_key1..5.mp3. We will map them.
# It lacks specific enter/space, so we will reuse generic keys for them to ensure sound.
afconvert -f WAVE -d LEI16 "$BASE/mx-blue/press_key1.mp3" Sources/Sounds/MX_Blue/1.wav
afconvert -f WAVE -d LEI16 "$BASE/mx-blue/press_key2.mp3" Sources/Sounds/MX_Blue/2.wav
afconvert -f WAVE -d LEI16 "$BASE/mx-blue/press_key3.mp3" Sources/Sounds/MX_Blue/3.wav
afconvert -f WAVE -d LEI16 "$BASE/mx-blue/press_key4.mp3" Sources/Sounds/MX_Blue/4.wav
afconvert -f WAVE -d LEI16 "$BASE/mx-blue/press_key5.mp3" Sources/Sounds/MX_Blue/5.wav
# Reuse for special keys
cp Sources/Sounds/MX_Blue/1.wav Sources/Sounds/MX_Blue/enter.wav
cp Sources/Sounds/MX_Blue/2.wav Sources/Sounds/MX_Blue/space.wav
cp Sources/Sounds/MX_Blue/3.wav Sources/Sounds/MX_Blue/backspace.wav
cp Sources/Sounds/MX_Blue/4.wav Sources/Sounds/MX_Blue/modifier.wav

# 2. Typewriter (Retro) - Source is already WAV? Check format.
# ls output showed .wav, but we should ensure format is correct for AVAudioPlayer (LEI16)
echo "Processing Typewriter..."
afconvert -f WAVE -d LEI16 "$BASE/typewriter/key.wav" Sources/Sounds/Typewriter_New/1.wav
afconvert -f WAVE -d LEI16 "$BASE/typewriter/key2.wav" Sources/Sounds/Typewriter_New/2.wav
afconvert -f WAVE -d LEI16 "$BASE/typewriter/enter.wav" Sources/Sounds/Typewriter_New/enter.wav
afconvert -f WAVE -d LEI16 "$BASE/typewriter/space.wav" Sources/Sounds/Typewriter_New/space.wav
afconvert -f WAVE -d LEI16 "$BASE/typewriter/delete.wav" Sources/Sounds/Typewriter_New/backspace.wav
# Create copies for variety
cp Sources/Sounds/Typewriter_New/1.wav Sources/Sounds/Typewriter_New/3.wav
cp Sources/Sounds/Typewriter_New/2.wav Sources/Sounds/Typewriter_New/4.wav

# 3. Opera GX (Digital/Fun) - Source is WAV
echo "Processing Opera GX..."
afconvert -f WAVE -d LEI16 "$BASE/opera-gx/1real.wav" Sources/Sounds/Opera_GX/1.wav
afconvert -f WAVE -d LEI16 "$BASE/opera-gx/2real.wav" Sources/Sounds/Opera_GX/2.wav
afconvert -f WAVE -d LEI16 "$BASE/opera-gx/3real.wav" Sources/Sounds/Opera_GX/3.wav
afconvert -f WAVE -d LEI16 "$BASE/opera-gx/enter.wav" Sources/Sounds/Opera_GX/enter.wav
afconvert -f WAVE -d LEI16 "$BASE/opera-gx/space.wav" Sources/Sounds/Opera_GX/space.wav
afconvert -f WAVE -d LEI16 "$BASE/opera-gx/backspace.wav" Sources/Sounds/Opera_GX/backspace.wav

echo "Done adding new profiles."
