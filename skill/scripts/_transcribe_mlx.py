#!/usr/bin/env python3
"""Transcribe audio with mlx-whisper. Called by transcribe.sh."""
import sys
import time
import mlx_whisper

def main():
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <audio_file> <output_file> <model> <language>", file=sys.stderr)
        sys.exit(1)

    audio_file, output_file, model_id, lang = sys.argv[1:]

    print(f"Model: {model_id}")
    t0 = time.time()
    result = mlx_whisper.transcribe(audio_file, path_or_hf_repo=model_id, language=lang, verbose=True)
    elapsed = time.time() - t0

    segs = result["segments"]
    dur = segs[-1]["end"] if segs else 0

    with open(output_file, "w") as f:
        for seg in segs:
            f.write(f'[{seg["start"]:.0f}s - {seg["end"]:.0f}s] {seg["text"]}\n')

    print(f"Done: {elapsed:.0f}s for {dur:.0f}s audio ({dur/elapsed:.1f}x realtime)")

if __name__ == "__main__":
    main()
