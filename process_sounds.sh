#!/bin/bash

# Ensure directories exist
mkdir -p Sources/Sounds/iPhone
mkdir -p Sources/Sounds/BlackBerry

# 1. iPhone Sounds (from keyboardsounds/profiles/ios MP3s)
# Using these because they are verified ~78ms duration, unlike the 4ms caf files from iOSSystemSounds
echo "Processing iPhone sounds (from keyboardsounds/profiles/ios)..."
IOS_SRC="temp_assets/keyboardsounds/keyboardsounds/profiles/ios"
afconvert -f WAVE -d LEI16 "$IOS_SRC/key.mp3" Sources/Sounds/iPhone/1.wav
cp Sources/Sounds/iPhone/1.wav Sources/Sounds/iPhone/2.wav
cp Sources/Sounds/iPhone/1.wav Sources/Sounds/iPhone/3.wav
cp Sources/Sounds/iPhone/1.wav Sources/Sounds/iPhone/4.wav
afconvert -f WAVE -d LEI16 "$IOS_SRC/back.mp3" Sources/Sounds/iPhone/backspace.wav
afconvert -f WAVE -d LEI16 "$IOS_SRC/alt.mp3" Sources/Sounds/iPhone/modifier.wav
cp Sources/Sounds/iPhone/1.wav Sources/Sounds/iPhone/enter.wav
cp Sources/Sounds/iPhone/1.wav Sources/Sounds/iPhone/space.wav

# 2. BlackBerry Sounds (using Holy Panda MP3s as proxy)
echo "Processing BlackBerry (Holy Panda) sounds..."
HP_SRC="temp_assets/keyboardsounds/keyboardsounds/profiles/holy-panda"
afconvert -f WAVE -d LEI16 "$HP_SRC/press_key1.mp3" Sources/Sounds/BlackBerry/1.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_key2.mp3" Sources/Sounds/BlackBerry/2.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_key3.mp3" Sources/Sounds/BlackBerry/3.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_key4.mp3" Sources/Sounds/BlackBerry/4.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_key5.mp3" Sources/Sounds/BlackBerry/5.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_enter.mp3" Sources/Sounds/BlackBerry/enter.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_space.mp3" Sources/Sounds/BlackBerry/space.wav
afconvert -f WAVE -d LEI16 "$HP_SRC/press_back.mp3" Sources/Sounds/BlackBerry/backspace.wav

echo "Done processing sounds."
