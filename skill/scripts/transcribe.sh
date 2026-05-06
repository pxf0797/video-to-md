#!/bin/bash
# Download audio and transcribe with mlx-whisper (Apple GPU accelerated)
# Usage: ./transcribe.sh <video-url> [model] [language]
#   model: tiny, small, medium, large-v3-turbo, large-v3 (default)
#   NOTE: large-v3-turbo uses 'whisper-large-v3-turbo' (no -mlx suffix)
#   language: zh (default), en, etc.
# Falls back to openai-whisper if mlx-whisper is unavailable.

set -e

URL="${1:?Usage: $0 <video-url> [model] [language]}"
MODEL="${2:-large-v3}"
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
# --remote-components ejs:github prevents truncated downloads from JS challenge failures
yt-dlp -f "bestaudio" --no-playlist --remote-components ejs:github -o "$OUTDIR/$VIDEO_ID.%(ext)s" "$URL"

# Find the downloaded file (extension varies: webm, m4a, opus)
AUDIO_FILE=$(ls "$OUTDIR/$VIDEO_ID".* 2>/dev/null | grep -v '.txt$' | head -1) || true
if [ -z "$AUDIO_FILE" ]; then
    echo "ERROR: Audio download failed"
    exit 1
fi
echo "Audio: $AUDIO_FILE ($(du -h "$AUDIO_FILE" | cut -f1))"

# Verify audio is complete (not truncated)
ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
echo "Audio duration: ${ACTUAL_DURATION}s"

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

# Clean up audio file (transcription txt left for caller to process then delete)
rm -f "$AUDIO_FILE"

if [ -f "$OUTFILE" ]; then
    LINES=$(wc -l < "$OUTFILE")
    echo "=== Output: $OUTFILE ($LINES lines) ==="
    echo "$OUTFILE"
else
    echo "ERROR: Transcription failed"
    exit 1
fi
