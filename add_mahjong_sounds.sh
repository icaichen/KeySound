#!/bin/bash

# Ensure directories exist
mkdir -p Sources/Sounds/Mahjong
mkdir -p Sources/Sounds/Creamy
mkdir -p Sources/Sounds/Thocky

# Base path
BASE="temp_assets/keyboardsounds/keyboardsounds/profiles"

# 1. Mahjong (Gateron Black Ink - Deep/Thocky)
echo "Processing Mahjong (Gateron Black Ink)..."
INK_SRC="$BASE/gateron-black-ink"
afconvert -f WAVE -d LEI16 "$INK_SRC/press_key1.mp3" Sources/Sounds/Mahjong/1.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_key2.mp3" Sources/Sounds/Mahjong/2.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_key3.mp3" Sources/Sounds/Mahjong/3.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_key4.mp3" Sources/Sounds/Mahjong/4.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_key5.mp3" Sources/Sounds/Mahjong/5.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_enter.mp3" Sources/Sounds/Mahjong/enter.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_space.mp3" Sources/Sounds/Mahjong/space.wav
afconvert -f WAVE -d LEI16 "$INK_SRC/press_back.mp3" Sources/Sounds/Mahjong/backspace.wav
# Use key1 for modifier default
cp Sources/Sounds/Mahjong/1.wav Sources/Sounds/Mahjong/modifier.wav

# 2. Creamy (NK Cream)
echo "Processing Creamy (NK Cream)..."
CREAM_SRC="$BASE/nk-cream"
afconvert -f WAVE -d LEI16 "$CREAM_SRC/a.wav" Sources/Sounds/Creamy/1.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/b.wav" Sources/Sounds/Creamy/2.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/c.wav" Sources/Sounds/Creamy/3.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/d.wav" Sources/Sounds/Creamy/4.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/e.wav" Sources/Sounds/Creamy/5.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/enter.wav" Sources/Sounds/Creamy/enter.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/space.wav" Sources/Sounds/Creamy/space.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/backspace.wav" Sources/Sounds/Creamy/backspace.wav
afconvert -f WAVE -d LEI16 "$CREAM_SRC/shift.wav" Sources/Sounds/Creamy/modifier.wav

# 3. Thocky (Banana Split)
echo "Processing Thocky (Banana Split)..."
BANANA_SRC="$BASE/banana-split"
afconvert -f WAVE -d LEI16 "$BANANA_SRC/banana-l-1.wav" Sources/Sounds/Thocky/1.wav
afconvert -f WAVE -d LEI16 "$BANANA_SRC/banana-l-2.wav" Sources/Sounds/Thocky/2.wav
afconvert -f WAVE -d LEI16 "$BANANA_SRC/banana-l-3.wav" Sources/Sounds/Thocky/3.wav
afconvert -f WAVE -d LEI16 "$BANANA_SRC/banana-l-4.wav" Sources/Sounds/Thocky/4.wav
afconvert -f WAVE -d LEI16 "$BANANA_SRC/banana-l-5.wav" Sources/Sounds/Thocky/5.wav
# Reuse keys for special keys since Banana Split doesn't have dedicated ones
cp Sources/Sounds/Thocky/1.wav Sources/Sounds/Thocky/enter.wav
cp Sources/Sounds/Thocky/2.wav Sources/Sounds/Thocky/space.wav
cp Sources/Sounds/Thocky/3.wav Sources/Sounds/Thocky/backspace.wav
cp Sources/Sounds/Thocky/4.wav Sources/Sounds/Thocky/modifier.wav

echo "Done adding Mahjong and other custom sounds."
