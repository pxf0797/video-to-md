#!/bin/bash
# Download audio and transcribe with mlx-whisper (Apple GPU accelerated)
# Usage: ./transcribe.sh <video-url> [model] [language]
#   model: tiny, small (default), medium, large-v3-turbo, large-v3
#   NOTE: large-v3-turbo uses 'whisper-large-v3-turbo' (no -mlx suffix)
#   language: zh (default), en, etc.
# Falls back to openai-whisper if mlx-whisper is unavailable.

set -e

URL="${1:?Usage: $0 <video-url> [model] [language]}"
MODEL="${2:-small}"
LANG="${3:-zh}"

# large-v3-turbo has no -mlx suffix (exception to naming pattern)
if [ "$MODEL" = "large-v3-turbo" ]; then
    MLX_MODEL="mlx-community/whisper-large-v3-turbo"
else
    MLX_MODEL="mlx-community/whisper-${MODEL}-mlx"
fi
OUTDIR="/tmp/whisper_output"
mkdir -p "$OUTDIR"

VIDEO_ID=$(echo "$URL" | grep -oE '[A-Za-z0-9_-]{11}' | head -1 || echo "video")
OUTFILE="$OUTDIR/$VIDEO_ID.txt"

echo "=== Step 1: Downloading audio ==="
# Download audio-only stream directly (no --extract-audio or --audio-format needed)
yt-dlp -f "bestaudio" --no-playlist -o "$OUTDIR/$VIDEO_ID.%(ext)s" "$URL"

# Find the downloaded file (extension varies: webm, m4a, opus)
AUDIO_FILE=$(ls "$OUTDIR/$VIDEO_ID".* 2>/dev/null | grep -v '.txt$' | head -1) || true
if [ -z "$AUDIO_FILE" ]; then
    echo "ERROR: Audio download failed"
    exit 1
fi
echo "Audio: $AUDIO_FILE ($(du -h "$AUDIO_FILE" | cut -f1))"

echo "=== Step 2: Transcribing ==="
if pip show mlx-whisper > /dev/null 2>&1; then
    echo "Engine: mlx-whisper ($MLX_MODEL)"
    python3 /Users/xfpan/.claude/skills/video-to-md/scripts/_transcribe_mlx.py "$AUDIO_FILE" "$OUTFILE" "$MLX_MODEL" "$LANG" 2>&1 || {
        echo "=== Falling back to openai-whisper ==="
        whisper "$AUDIO_FILE" --model "$MODEL" --language "$LANG" --output_format txt --output_dir "$OUTDIR" --verbose True 2>&1
        TXT_FILE=$(ls "$OUTDIR/$VIDEO_ID"*.txt 2>/dev/null | head -1)
        [ -n "$TXT_FILE" ] && [ "$TXT_FILE" != "$OUTFILE" ] && mv "$TXT_FILE" "$OUTFILE"
    }
else
    echo "Engine: openai-whisper ($MODEL)"
    whisper "$AUDIO_FILE" --model "$MODEL" --language "$LANG" --output_format txt --output_dir "$OUTDIR" --verbose True 2>&1
    TXT_FILE=$(ls "$OUTDIR/$VIDEO_ID"*.txt 2>/dev/null | head -1)
    [ -n "$TXT_FILE" ] && [ "$TXT_FILE" != "$OUTFILE" ] && mv "$TXT_FILE" "$OUTFILE"
fi

rm -f "$AUDIO_FILE" "$OUTDIR/$VIDEO_ID.m4a"

if [ -f "$OUTFILE" ]; then
    LINES=$(wc -l < "$OUTFILE")
    echo "=== Output: $OUTFILE ($LINES lines) ==="
    echo "$OUTFILE"
else
    echo "ERROR: Transcription failed"
    exit 1
fi
