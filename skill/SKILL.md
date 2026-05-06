---
name: video-to-md
description: Download a video's audio with yt-dlp, transcribe it to text with Whisper, and produce a well-structured markdown summary with chapter timestamps, core concepts, and comparison tables. Use when the user asks to organize, summarize, or extract content from a video into a markdown file. Triggers on requests like "帮我整理视频内容", "summarize this video", "extract content from this YouTube link", "视频转文字整理", or similar.
---

# Video to Markdown

Extract, transcribe, and organize video content into a structured markdown file.

## Prerequisites

- `deno` — JS runtime for yt-dlp YouTube extraction (avoids "No supported JS runtime" warning)
- `yt-dlp` — audio download
- `ffmpeg` — audio probe/conversion
- `mlx-whisper` — transcription with Apple Silicon GPU acceleration **(primary, ~10x realtime)**

Verify: `which deno yt-dlp ffmpeg && pip show mlx-whisper 2>/dev/null | grep '^Name:'`

**Audio format:** Download the audio-only stream directly (`-f bestaudio`). mlx-whisper reads webm/opus natively — no `--extract-audio --audio-format mp3` conversion needed.

## Parallel Processing

When multiple video URLs are provided, process them concurrently with unique identifiers to avoid file conflicts:

- **Video ID marker**: Extract the 11-character YouTube ID from each URL with `grep -oE '[A-Za-z0-9_-]{11}'`
- **Audio files**: `/tmp/video_<VIDEO_ID>.%(ext)s` — each video's audio is isolated
- **Transcript files**: `/tmp/whisper_output/<VIDEO_ID>.txt` — each transcript is isolated
- **Cleanup**: Delete audio and transcript temp files after the final markdown is saved

Workflow for N videos:
1. **Gather metadata** for all URLs in parallel (single batch of `yt-dlp --skip-download`)
2. **Choose one model** for all videos with a single selection prompt
3. **Download audio** for all videos in parallel (unique filenames, no conflicts)
4. **Transcribe** all videos in parallel (unique output files, no conflicts)
5. **Process transcripts** sequentially to generate each markdown
6. **Clean up** all temp audio and transcript files

For a single video, the same identifiable naming applies — it ensures no collision with past or future runs.

## Transcription Engine Selection

### Primary: mlx-whisper (Apple GPU, fastest)

Uses Apple Neural Engine + GPU. Public models at `mlx-community/whisper-{size}-mlx`. On M-series Mac:

| Model | Speed (vs realtime) | 10min video | 40min video |
|---|---|---|---|
| `mlx-community/whisper-tiny-mlx` | ~40x | ~15s | ~1min |
| `mlx-community/whisper-small-mlx` | ~10x | ~1min | ~4min |
| `mlx-community/whisper-medium-mlx` | ~5x | ~2min | ~8min |
| `mlx-community/whisper-large-v3-turbo` | ~3x | ~3min | ~13min |
| `mlx-community/whisper-large-v3-mlx` | ~2x | ~5min | ~20min |

Models are downloaded from HuggingFace on first use and cached at `~/.cache/huggingface/hub/`. First run incurs a one-time download (small ≈ 500MB, ~1-2 min; large-v3 ≈ 3GB, ~10min). Subsequent runs are instant.

**Naming exception**: `large-v3-turbo` repo is `mlx-community/whisper-large-v3-turbo` (no `-mlx` suffix). All other models follow `whisper-{size}-mlx` pattern.

### Fallback: openai-whisper (CPU)

Runs CPU FP32 — about **3-4x slower** than mlx-whisper. Only use if mlx-whisper is completely unavailable.

## Workflow

### Step 1: Gather metadata

Extract the video ID from the URL for use as a unique file marker throughout the workflow:

```bash
VIDEO_ID=$(echo "<URL>" | grep -oE '[A-Za-z0-9_-]{11}' | head -1)
```

Gather metadata (for multiple URLs, run these in parallel per URL):

```bash
yt-dlp --skip-download --print "%(title)s\n---\n%(description)s\n---\n%(channel)s\n---\n%(duration)s\n---\n%(upload_date)s" "<URL>"
```

Check subtitles:

```bash
yt-dlp --skip-download --list-subs "<URL>"
```

Note the duration in seconds (store as `EXPECTED_DURATION` for later verification). Convert to minutes for the model selection prompt.

### Step 2: Choose model (MANDATORY — do not skip)

Check which mlx-whisper models are already cached:

```bash
ls ~/.cache/huggingface/hub/ 2>/dev/null | grep whisper | sed 's/models--mlx-community--whisper-//;s/-mlx//' || echo "none cached yet"
```

Print the selection menu, then use **ScheduleWakeup** to implement a real 60-second auto-proceed timeout (ScheduleWakeup minimum is 60s):

**Implementation steps:**

1. **Print the menu** as text output with estimated times:

```
选择转录模型（视频约 X 分钟，60s 无操作自动选 large-v3）：

1) tiny           — ~40x 实时，~Xs
2) small          — ~10x 实时，~Xs
3) medium         — ~5x 实时，~Xs
4) large-v3-turbo — ~3x 实时，~Xs
5) large-v3（推荐）— ~2x 实时，~Xs，默认

回复数字选择模型，或等待 60s 自动使用 large-v3：
```

2. **Schedule a 60-second wakeup** using the `ScheduleWakeup` tool. **Record the returned job ID** for later cancellation. The prompt must be self-contained with URL, title, duration, and language so the wakeup can proceed autonomously:

```
ScheduleWakeup(delaySeconds=60, reason="model selection timeout", prompt="用户未选择模型，超时。使用默认 large-v3 模型（mlx-community/whisper-large-v3-mlx）继续转录。视频URL: <URL>，标题: <title>，时长约<duration>秒，中文音频。请执行 Step 3：下载音频并转录。")
// Returns: {"id": "<WAKEUP_JOB_ID>", ...} — save this ID
```

3. **Wait for user response.** Three outcomes:
   - **User replies with `1`-`5`** → **IMMEDIATELY cancel the wakeup** with `CronDelete(id="<WAKEUP_JOB_ID>")`, then map to the corresponding model and proceed.
   - **User replies with anything else** → cancel wakeup, treat as `large-v3`
   - **No reply within 60s** → ScheduleWakeup fires, injecting a prompt that tells Claude to proceed with `large-v3`

**CRITICAL: Always cancel the wakeup when the user manually selects a model.** Otherwise the wakeup will fire later (after the next idle period) and inject a stale "timeout" prompt that confuses the next turn. Use `CronDelete` with the job ID returned by `ScheduleWakeup`.

**Model map:**
- `1` → `MLX_MODEL="mlx-community/whisper-tiny-mlx"`
- `2` → `MLX_MODEL="mlx-community/whisper-small-mlx"`
- `3` → `MLX_MODEL="mlx-community/whisper-medium-mlx"`
- `4` → `MLX_MODEL="mlx-community/whisper-large-v3-turbo"` (note: no `-mlx` suffix)
- `5` or timeout/any other reply → `MLX_MODEL="mlx-community/whisper-large-v3-mlx"`

For Bilibili / Chinese title → auto `zh` language, no need to ask.

### Step 3: Download audio and transcribe

**Download audio-only stream directly** — no `--extract-audio` or `--audio-format mp3` needed. yt-dlp downloads the opus/webm audio stream directly (~6MB for 8min). mlx-whisper reads webm/opus natively — conversion is unnecessary and was the root cause of slow downloads.

**CRITICAL — always include `--remote-components ejs:github`**: Without this flag, yt-dlp's JS challenge solver may fail silently, causing YouTube to serve a **truncated audio stream** (e.g., only 9MB of a 23MB file, resulting in 10 minutes of a 25-minute video). The `ejs:github` component provides the solver script needed for complete, unthrottled downloads.

```bash
yt-dlp -f "bestaudio" --no-playlist --remote-components ejs:github -o "/tmp/video_${VIDEO_ID}.%(ext)s" "<URL>"
# outputs: /tmp/video_CYzQnkw99pQ.webm (or .m4a)
```

Find the downloaded file and set `AUDIO_FILE`:

```bash
AUDIO_FILE=$(ls /tmp/video_${VIDEO_ID}.* 2>/dev/null | grep -v txt | head -1)
```

**MANDATORY — verify audio is complete** by checking the actual duration against the expected duration from Step 1. YouTube throttling/truncation can produce partial files without yt-dlp reporting an error. Tolerance: ±3 seconds.

```bash
ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
# Compare ACTUAL_DURATION against EXPECTED_DURATION from Step 1
# If |ACTUAL - EXPECTED| > 3s → download was truncated → re-download
```

If the duration mismatch exceeds 3 seconds, delete the partial file and re-download. The `--remote-components ejs:github` flag above prevents this in most cases, but verification catches any remaining edge cases (e.g., network interruption).

Transcribe with the bundled `_transcribe_mlx.py` script. Check if the model is cached first — if not, warn about one-time download. Then run:

```bash
python3 <path-to-skill>/scripts/_transcribe_mlx.py "$AUDIO_FILE" "/tmp/whisper_output/${VIDEO_ID}.txt" "$MLX_MODEL" zh
```

The script takes 4 positional args: `<audio_file> <output_file> <model> <language>`. It supports webm, m4a, mp3, and any format ffmpeg can read.

**Do NOT use inline `python3 -c`** — shell escaping of f-strings and quotes causes silent failures.
**Do NOT use `--extract-audio --audio-format mp3`** — forces unnecessary video download + re-encode, 2-10x slower.

**Progress visibility:**
- mlx-whisper with `verbose=True` shows `tqdm` progress: `[00:05<00:30, 234.50frames/s]` — this means X seconds elapsed, Y seconds remaining
- For videos > 10 minutes, run in background and use `TaskOutput` to surface the progress to the user
- For videos < 10 minutes, run in foreground so the user sees the live progress bar
- When run in background, periodically call `TaskOutput` to check and report progress to the user

After completion verify:

```bash
wc -l /tmp/whisper_output/${VIDEO_ID}.txt
```

After the markdown is saved (Step 5), clean up all temp files:

```bash
rm -f /tmp/video_${VIDEO_ID}.* /tmp/whisper_output/${VIDEO_ID}.txt
```

For multi-video runs, clean up after all markdown files are saved to keep transcripts available for cross-reference during processing.

### Step 4: Read and organize the transcript

Read the full transcript (raw text, no punctuation, possible recognition errors). Use the video description's chapter timestamps to segment the content.

**Generate all three formats in a single markdown file** — follow the complete template in `references/output-format.md`:

| # | 格式 | 用途 | 详细程度 |
|---|---|---|---|
| 方式一 | 章节结构化 | 快速扫描，按章节找重点 | 中等 |
| 方式二 | 分层大纲 | 理解逻辑链条、论证层级 | 深 |
| 方式三 | 时间轴分段 | 精准定位每段内容，接近逐字稿 | 最深 |

Each format is a different lens on the same transcript. The formats are complementary — 方式一 for scan, 方式二 for logic, 方式三 for precision. Content should be consistent across formats, not duplicated.

Also include:
- **TL;DR** at top (2-3 sentences)
- **全篇回顾** at end (synthesis paragraph)
- **时间轴索引** table at end of 方式三

### Step 5: Save the file

Ensure the output directory exists, then save:

```bash
mkdir -p ./video-to-md
```

Get today's date for the filename prefix:

```bash
date +%Y%m%d
```

File name pattern:

```
./video-to-md/YYYYMMDD_<topic_keyword>_视频整理.md   (Chinese videos)
./video-to-md/YYYYMMDD_<topic_keyword>_summary.md    (English videos)
```

Example: `./video-to-md/20260504_纳瓦尔_性张力.md`

## Common Pitfalls

1. **WebFetch on YouTube fails** — YouTube returns 303 redirect. Use `yt-dlp` for all metadata.
2. **No subtitles available** — Most Chinese videos lack auto-captions. Transcribe from audio.
3. **mlx-whisper model download** — First use of a model downloads ~500MB-3GB from HuggingFace. Warn the user if uncached. The download is one-time; subsequent runs are instant.
4. **openai-whisper as fallback** — If mlx-whisper fails (network/auth), fall back to `openai-whisper` with locally cached models at `~/.cache/whisper/`.
5. **Background vs foreground** — Short videos (<10 min): run transcription in foreground for live progress. Long videos: run in background, use `TaskOutput` to relay progress to user.
6. **Model selection timeout** — Use `ScheduleWakeup(delaySeconds=60)` (the tool-enforced minimum) to auto-proceed after 60s of user inactivity. Do NOT use `sleep` loops, `read -t`, or background countdown processes — none of these work because Claude's conversation model is synchronous and Bash has no terminal stdin. ScheduleWakeup fires when the REPL is idle (waiting for input), which is exactly the state we need. **Always cancel the wakeup with `CronDelete` when the user manually selects a model** — otherwise the stale wakeup fires on the next idle turn and injects a confusing "timeout" message.
7. **Truncated audio downloads** — YouTube may serve incomplete audio streams when yt-dlp's JS challenge solver fails. The download reports success but the file is only a fraction of the expected size/duration. Always: (a) use `--remote-components ejs:github` in the download command, and (b) verify with `ffprobe` that the actual audio duration matches the expected duration from metadata. Mismatch > 3s → delete and re-download. See the Step 3 verification block for the exact commands.
8. **Stale temp files from previous runs** — `/tmp/video.webm` or `/tmp/whisper_output/video.txt` may exist from a prior session. Using video-ID-based filenames (`/tmp/video_<VIDEO_ID>.*`) eliminates this conflict. Always verify `ffprobe` duration against expected metadata — if a stale file matches the current video ID but has the wrong duration, `rm` it before re-downloading.
