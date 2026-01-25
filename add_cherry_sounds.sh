#!/bin/bash

# Ensure directories exist
mkdir -p Sources/Sounds/MX_Brown
mkdir -p Sources/Sounds/MX_Black

# Base path
BASE="temp_assets/keyboardsounds/keyboardsounds/profiles"

# 1. MX Brown (Tactile - Cherry Brown)
echo "Processing MX Brown..."
BROWN_SRC="$BASE/mx-brown"
afconvert -f WAVE -d LEI16 "$BROWN_SRC/press_key1.mp3" Sources/Sounds/MX_Brown/1.wav
afconvert -f WAVE -d LEI16 "$BROWN_SRC/press_key2.mp3" Sources/Sounds/MX_Brown/2.wav
afconvert -f WAVE -d LEI16 "$BROWN_SRC/press_key3.mp3" Sources/Sounds/MX_Brown/3.wav
afconvert -f WAVE -d LEI16 "$BROWN_SRC/press_key4.mp3" Sources/Sounds/MX_Brown/4.wav
afconvert -f WAVE -d LEI16 "$BROWN_SRC/press_key5.mp3" Sources/Sounds/MX_Brown/5.wav
# Reuse for special keys
cp Sources/Sounds/MX_Brown/1.wav Sources/Sounds/MX_Brown/enter.wav
cp Sources/Sounds/MX_Brown/2.wav Sources/Sounds/MX_Brown/space.wav
cp Sources/Sounds/MX_Brown/3.wav Sources/Sounds/MX_Brown/backspace.wav
cp Sources/Sounds/MX_Brown/4.wav Sources/Sounds/MX_Brown/modifier.wav

# 2. MX Black (Linear - Cherry Black)
echo "Processing MX Black..."
BLACK_SRC="$BASE/mx-black"
afconvert -f WAVE -d LEI16 "$BLACK_SRC/press_key1.mp3" Sources/Sounds/MX_Black/1.wav
afconvert -f WAVE -d LEI16 "$BLACK_SRC/press_key2.mp3" Sources/Sounds/MX_Black/2.wav
afconvert -f WAVE -d LEI16 "$BLACK_SRC/press_key3.mp3" Sources/Sounds/MX_Black/3.wav
afconvert -f WAVE -d LEI16 "$BLACK_SRC/press_key4.mp3" Sources/Sounds/MX_Black/4.wav
afconvert -f WAVE -d LEI16 "$BLACK_SRC/press_key5.mp3" Sources/Sounds/MX_Black/5.wav
# Reuse for special keys
cp Sources/Sounds/MX_Black/1.wav Sources/Sounds/MX_Black/enter.wav
cp Sources/Sounds/MX_Black/2.wav Sources/Sounds/MX_Black/space.wav
cp Sources/Sounds/MX_Black/3.wav Sources/Sounds/MX_Black/backspace.wav
cp Sources/Sounds/MX_Black/4.wav Sources/Sounds/MX_Black/modifier.wav

echo "Done adding MX Brown and Black."
