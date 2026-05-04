# video-to-md Skill 完整文档

> **版本**: 2026-05-04 | **作者**: Claude Code + 用户协作迭代
> **适用平台**: macOS (Apple Silicon) | **最低要求**: deno, yt-dlp, ffmpeg, mlx-whisper

---

## 一、概述

### 1.1 这是什么

`video-to-md` 是一个 Claude Code Skill，将任何视频（YouTube、Bilibili 等 yt-dlp 支持的平台）自动转换为结构化的 Markdown 文档。流程包括：

1. 提取元数据（标题、章节、时长）
2. 下载纯音频流（无需下载视频）
3. 使用 Apple GPU 加速的 Whisper 模型进行语音转录
4. 以**三种互补格式**整理内容并生成 `.md` 文件

### 1.2 触发方式

用户输入带有视频链接的请求时自动激活。触发词示例：

| 中文 | English |
|---|---|
| 帮我整理视频内容 | summarize this video |
| 视频转文字整理 | extract content from this YouTube link |
| /video-to-md `<URL>` | |

### 1.3 适用场景

| 视频类型 | 推荐用途 |
|---|---|
| 教育/知识类 | 深度学习，三种格式一次性获取 |
| 教程/操作指南 | 时间轴分段精确对照 |
| 评论/分析类 | 分层大纲理清论证逻辑 |
| 访谈/对话 | 章节结构 + 时间轴快速回顾 |
| 中文视频（无字幕） | **特别适合**——中文 YouTube 视频大多无自动字幕 |

---

## 二、使用方法

### 2.1 基本使用

```
/video-to-md https://www.youtube.com/watch?v=xxxxx
/video-to-md https://www.bilibili.com/video/BVxxxxx
```

### 2.2 交互流程

```
用户发送链接
    │
    ▼
[Step 1] 提取元数据（~3秒）
    │  - 标题、频道、时长、发布日期
    │  - 章节标记（如有）
    │  - 字幕检查（通常无）
    │
    ▼
[Step 2] 模型选择（15秒超时）
    │  ┌──────────────────────────────────────┐
    │  │ 选择转录模型（视频约 X 分钟）：        │
    │  │ 1) tiny     — ~40x 实时              │
    │  │ 2) small    — ~10x 实时，默认         │
    │  │ 3) medium   — ~5x 实时               │
    │  │ 4) large-v3-turbo — ~3x 实时         │
    │  │ 5) large-v3 — ~2x 实时               │
    │  │ 回复数字，15s 后默认 small            │
    │  └──────────────────────────────────────┘
    │  用户回复数字 / 15s 超时自动 small
    │
    ▼
[Step 3] 下载音频 + 转录（~数秒至数分钟）
    │  - yt-dlp 下载纯音频流（webm/opus，~6MB/8min）
    │  - ffprobe 验证音频完整性
    │  - mlx-whisper GPU 加速转录
    │  - 实时进度条显示
    │
    ▼
[Step 4] 读取转录 + 生成三种格式
    │  - 方式一：章节结构化（快速扫描）
    │  - 方式二：分层大纲（逻辑树）
    │  - 方式三：时间轴分段（逐段详情）
    │
    ▼
[Step 5] 保存到 ./video-to-md/YYYYMMDD_xxx.md
```

### 2.3 输出文件位置

```
当前工作目录/
└── video-to-md/
    ├── 20260504_真假好感判断_视频整理.md
    ├── 20260504_纳瓦尔_性张力.md
    └── ...
```

---

## 三、架构与目录结构

### 3.1 Skill 目录

```
~/.claude/skills/video-to-md/
├── SKILL.md                          # 主流程指令（Claude 执行依据）
├── scripts/
│   ├── transcribe.sh                 # 下载+转录主脚本（带回退）
│   └── _transcribe_mlx.py           # mlx-whisper Python 转录核心
└── references/
    └── output-format.md              # 三种输出格式模板 + 质量清单
```

### 3.2 打包分发

```bash
python3 ~/.claude/skills/skill-creator/scripts/package_skill.py \
    ~/.claude/skills/video-to-md \
    /path/to/output
```
生成 `video-to-md.skill` 文件（zip 格式，含 `.skill` 扩展名）。

---

## 四、技术原理

### 4.1 转录引擎选型

本 Skill 在开发过程中测试了多种 Whisper 方案，最终选定 mlx-whisper：

| 方案 | 速度 (Apple Silicon) | 本地模型 | 结论 |
|---|---|---|---|
| **mlx-whisper** | **10-40x 实时** | HF Hub 缓存 | ✅ **首选**——Apple Neural Engine + GPU |
| openai-whisper | 4-6x 实时 | ~/.cache/whisper/ | ⚠️ 回退方案——纯 CPU FP32 |
| faster-whisper | 理论快 | CTranslate2 缓存 | ❌ 模型下载需 HF 认证，首次失败率高 |
| whisper.cpp | 理论极快 | 需 brew 安装 | ❌ 未测试，需额外安装步骤 |

**关键发现**: mlx-whisper 的 `mlx-community/whisper-*` 模型是**公开的**，无需 HuggingFace token。之前的 401 错误是因为传了错误的 repo ID（如 `whisper-large-v3-turbo-mlx` 实际应为 `whisper-large-v3-turbo`，无 `-mlx` 后缀）。

### 4.2 音频下载优化

**迭代历程**（按时间顺序）：

| 阶段 | 命令 | 问题 |
|---|---|---|
| V1 | `-f bestaudio[ext=m4a] --extract-audio --audio-format mp3` | 下载完整视频→提取音轨→转码 mp3，40MB+，2分钟超时 |
| V2 | `-f bestaudio --no-playlist` | 直接下载 opus/webm 音频流，6MB/8min，3秒完成 |
| V3 (当前) | `-f bestaudio --no-playlist --remote-components ejs:github` | 增加 JS 挑战解决器，防止 YouTube 截断音频 |

**核心认知**: mlx-whisper 原生支持 webm/opus——无需任何转码。`--extract-audio --audio-format mp3` 不仅慢，而且浪费。

### 4.3 音频完整性验证

YouTube 可能在 JS 挑战失败时提供截断的音频流（yt-dlp 不报错，文件大小看起来正常，但实际只含部分时长）。Skill 通过两步防护：

1. `--remote-components ejs:github`：启用完整 JS 挑战解决，从根本上避免截断
2. `ffprobe` 校验：对比实际音频时长与元数据时长，差值 > 3s 则重新下载

### 4.4 模型选择超时机制

Claude 的对话模型是**同步阻塞**的——输出消息后必须等待用户回复。以下方案均失败：

| 方案 | 失败原因 |
|---|---|
| `sleep` + `echo` 倒计时循环 | Claude 无法同时"倒计时"和"等待输入" |
| `read -t 15` | Bash tool 无终端 stdin |
| Python `threading.Timer` | 内联代码有 shell 转义问题 |

**最终方案**: `ScheduleWakeup(delaySeconds=15)` —— 这是一个 Claude Code 系统工具，当 REPL 空闲（等待用户输入）时触发。15 秒内用户回复 → 正常处理；15 秒无人回复 → ScheduleWakeup 注入提示 → 自动使用 `small` 继续。

---

## 五、模型参考

### 5.1 可用模型清单

所有模型均为 `mlx-community` 下的公开模型，首次使用自动从 HuggingFace 下载。

| # | 模型名 | HF Repo ID | 大小 | 速度 | 适用场景 |
|---|---|---|---|---|---|
| 1 | tiny | `mlx-community/whisper-tiny-mlx` | ~150MB | ~40x | 快速预览 |
| 2 | **small** (默认) | `mlx-community/whisper-small-mlx` | ~500MB | ~10x | **日常转录** |
| 3 | medium | `mlx-community/whisper-medium-mlx` | ~1.5GB | ~5x | 高要求内容 |
| 4 | large-v3-turbo | `mlx-community/whisper-large-v3-turbo` | ~2GB | ~3x | 大模型加速版 |
| 5 | large-v3 | `mlx-community/whisper-large-v3-mlx` | ~2.9GB | ~2x | 最高精度 |

> ⚠️ **命名例外**: `large-v3-turbo` 的 repo ID 为 `whisper-large-v3-turbo`（**无 `-mlx` 后缀**）。其余四个模型遵循 `whisper-{size}-mlx` 模式。`transcribe.sh` 中有条件判断处理此例外。

### 5.2 模型缓存位置

```
~/.cache/huggingface/hub/models--mlx-community--whisper-{model}/
```

### 5.3 预下载大模型

首次使用大模型（medium 及以上）时，mlx-whisper 的单线程下载可能很慢。推荐提前用 `hf` CLI 多线程下载：

```bash
HF_HUB_ENABLE_HF_TRANSFER=1 hf download mlx-community/whisper-large-v3-mlx
```

---

## 六、输出格式详解

每个视频生成 **一个包含三种格式的 Markdown 文件**：

### 6.1 方式一：章节结构化

遵循视频自带的章节标记，每个章节提取：

```
### 一、章节标题（timestamp）

**核心概念一句话**

解释段落

> 原话金句

| 维度 | A | B |
|---|---|---|
| xxx | xxx | xxx |

---
### 章节总结
| 章节 | 核心要点 | 时间戳 |
```

**适合**: 快速浏览、按章节查找

### 6.2 方式二：分层大纲

重新组织为嵌套逻辑树，保留论证链条：

```
### 核心论点 1：主论点
- 子论点 1.1
  - 论据
  - 案例
- 子论点 1.2
  - 细节
  - 反例/边界

---
### 大纲全景
1. 核心论点1
   1.1 子论点
      ├ 论据
      └ 案例
```

**适合**: 理解逻辑关系、归纳知识体系

### 6.3 方式三：时间轴分段

按 1-5 分钟段落切分，接近逐字稿级别：

```
### [00:00 – 02:30] 段落标题

逐段详细笔记，保留原话和案例。

### [02:30 – 05:00] 段落标题
...

---
### 时间轴索引
| 时间段 | 内容要点 | 关键术语 |
```

**适合**: 需要回看原视频、精准定位

---

## 七、故障排查

### 7.1 常见问题

| 问题 | 症状 | 解决 |
|---|---|---|
| 音频下载慢/超时 | 下载耗时 > 1min | 确认用了 `-f bestaudio`，没用 `--extract-audio` |
| 音频截断 | 转录只有视频一半长 | 检查 `--remote-components ejs:github`，重试 |
| 模型下载 401 错误 | `Repository Not Found` | 检查模型名——特别是 turbo 的命名例外 |
| deno 未找到 | `No supported JS runtime` 警告 | `export PATH="$HOME/.deno/bin:$PATH"` |
| 转录无进度 | 长时间无输出 | 确认 `verbose=True`，短视频前台运行 |
| 模型选择不自动超时 | 等了很久没反应 | 确认使用了 `ScheduleWakeup`，不是 `sleep`/`read -t` |

### 7.2 调试检查

```bash
# 检查环境
which deno yt-dlp ffmpeg
pip show mlx-whisper | grep Version

# 检查模型缓存
ls ~/.cache/huggingface/hub/ | grep whisper

# 检查音频完整性
ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 /tmp/video.webm

# 手动测试转录
python3 ~/.claude/skills/video-to-md/scripts/_transcribe_mlx.py \
    /tmp/test.mp3 /tmp/out.txt mlx-community/whisper-small-mlx zh
```

---

## 八、维护指南

### 8.1 添加新模型

1. 在 HuggingFace 上确认模型存在（`hf models ls --search whisper --author mlx-community`）
2. 在 SKILL.md 速度表中添加新行
3. 在 SKILL.md Step 2 菜单中添加选项编号
4. 在 SKILL.md Model map 中添加映射
5. 在 `transcribe.sh` 中添加命名例外（如果命名模式不同）
6. 用 20s 测试音频验证：`python3 _transcribe_mlx.py test_20s.mp3 out.txt <new-model> zh`

### 8.2 更新依赖

```bash
pip install --upgrade mlx-whisper
pip install --upgrade yt-dlp
deno upgrade
```

### 8.3 修改输出格式

编辑 `references/output-format.md`，然后运行：
```bash
python3 ~/.claude/skills/skill-creator/scripts/package_skill.py \
    ~/.claude/skills/video-to-md ~/claude
```

### 8.4 已知限制

| 限制 | 说明 |
|---|---|
| 长视频 (>2h) | 转录时间较长，建议用 medium 或 small |
| 多语言混合 | mlx-whisper 一次只能指定一种语言 |
| 音乐/噪音 | 背景音乐可能影响识别，纯人声效果最佳 |
| YouTube 地区限制 | 部分视频可能需要代理 |
| ScheduleWakeup | 仅在 Claude Code REPL 模式下有效 |

---

## 九、迭代历史

| 日期 | 变更 | 动机 |
|---|---|---|
| 2026-05-03 | 初始版本——openai-whisper + yt-dlp | 首次实现视频转录链路 |
| 2026-05-04 | 切换到 mlx-whisper (Apple GPU) | 速度从 4x 提升到 10-40x 实时 |
| 2026-05-04 | 删除 openai-whisper 模型 | 统一使用 mlx-whisper |
| 2026-05-04 | 去掉 `--extract-audio --audio-format mp3` | 消除无用的下载+转码，6MB vs 40MB |
| 2026-05-04 | 安装 deno、添加 `--remote-components ejs:github` | 解决 YouTube JS 挑战导致的截断 |
| 2026-05-04 | 添加 `ffprobe` 音频完整性校验 | 防范静默截断 |
| 2026-05-04 | 修复 turbo 模型命名 | 发现 turbo 无 `-mlx` 后缀 |
| 2026-05-04 | 模型选择改用 ScheduleWakeup | 前 4 种方案均因 Claude 同步模型限制而失败 |
| 2026-05-04 | 三种输出格式合并 | 用户要求章节+大纲+时间轴一起生成 |
| 2026-05-04 | 使用 `hf download` 预下载大模型 | mlx-whisper 单线程下载大型模型太慢 |

---

## 十、脚本参考

### 10.1 `transcribe.sh`

完整的下载+转录流程脚本，可独立调用：

```bash
./transcribe.sh <video-url> [model] [language]
./transcribe.sh "https://youtube.com/watch?v=xxx" medium zh
```

**逻辑**:
1. yt-dlp 下载纯音频流（webm/opus）
2. 查找下载文件（自动适配扩展名）
3. 优先使用 mlx-whisper 转录
4. 如果 mlx-whisper 不可用，回退到 openai-whisper
5. 清理临时音频文件
6. 输出转录文件路径

### 10.2 `_transcribe_mlx.py`

mlx-whisper 转录核心，接受 4 个位置参数：

```
python3 _transcribe_mlx.py <audio_file> <output_file> <model> <language>
```

**注意事项**:
- 使用 `segs[-1]["end"]` 获取音频时长（mlx-whisper 的 result dict **没有** `duration` 键）
- `verbose=True` 输出 tqdm 实时进度条
- 支持 webm、m4a、mp3、opus 等 ffmpeg 可读的所有格式

---

## 十一、给后续开发者的建议

1. **不要使用内联 `python3 -c`**：shell 对 f-string 中 `${}` 的展开会破坏代码。始终使用独立的 `.py` 文件或 heredoc（带引号分隔符）。

2. **测试新模型前先用 20s 音频片段**：`ffmpeg -i input.mp3 -t 20 -c copy test_20s.mp3`。完整视频测试太慢。

3. **HuggingFace 下载取决于网络**：无 token 的下载速度约 1-2MB/s。在国内网络可能需要代理或镜像。`hf download` 比 mlx-whisper 的单线程下载快很多。

4. **每次修改 SKILL.md 后都要重新打包**：`package_skill.py` 既验证又打包。未经验证的 skill 可能加载失败。

5. **Claude 的同步模型是核心约束**：任何涉及"等待用户输入的同时做其他事"的设计都需要使用 ScheduleWakeup 等系统工具，普通 shell 技巧不适用。
