# video-to-md

> Claude Code Skill：一键将视频转录为结构化 Markdown 文档，支持三种格式。

## 功能

将 YouTube / Bilibili 等任意视频自动转换为详细的结构化文档：

1. **下载纯音频流** — 不下载视频，仅取 opus/webm 音频（~6MB/8min）
2. **GPU 加速转录** — Apple Silicon + mlx-whisper，10-40x 实时速度
3. **三种格式输出** — 章节结构化 + 分层大纲 + 时间轴分段（一份文件包含全部）

## 快速开始

### 前置依赖

```bash
# macOS (Apple Silicon)
brew install ffmpeg deno
pip install yt-dlp mlx-whisper
```

### 安装 Skill

将 `video-to-md.skill` 拖入 Claude Code 的 Skills 管理面板，或通过 CLI 安装。

### 使用

```
/video-to-md https://www.youtube.com/watch?v=xxxxx
/video-to-md https://www.bilibili.com/video/BVxxxxx
```

流程：提取元数据 → 选择转录模型（60s 超时默认 small）→ 下载+转录 → 生成 Markdown → 保存到 `./video-to-md/`

## 输出示例

每份文档包含三个视图：

| 格式 | 用途 | 详细度 |
|---|---|---|
| **方式一：章节结构化** | 快速扫描，按章节找重点 | ⭐⭐ |
| **方式二：分层大纲** | 理解逻辑链条、论证层级 | ⭐⭐⭐ |
| **方式三：时间轴分段** | 精准定位每段，接近逐字稿 | ⭐⭐⭐⭐ |

示例输出见 `docs/` 目录下的完整文档。

## 模型

| 模型 | 速度 | 适用场景 |
|---|---|---|
| tiny | ~40x | 快速预览 |
| **small (默认)** | **~10x** | **日常转录** |
| medium | ~5x | 高要求内容 |
| large-v3-turbo | ~3x | 大模型加速版 |
| large-v3 | ~2x | 最高精度 |

## 文件结构

```
skill/
├── SKILL.md                 # 主流程指令
├── scripts/
│   ├── transcribe.sh        # 下载+转录脚本（带回退）
│   └── _transcribe_mlx.py   # mlx-whisper 转录核心
└── references/
    └── output-format.md     # 三种输出格式模板

docs/
└── video-to-md_完整文档.md   # 完整技术文档

dist/
└── video-to-md.skill        # 打包的 Skill 文件
```

## 技术亮点

- **Apple GPU 加速**：使用 mlx-whisper 调用 Apple Neural Engine，比 CPU 方案快 3-7 倍
- **零转码**：webm/opus 原生支持，无需 mp3 转换
- **完整性校验**：ffprobe 验证音频时长，防范 YouTube 截断
- **超时自动执行**：ScheduleWakeup 实现模型选择的 60s 无人值守超时

## 文档

完整文档见 [docs/video-to-md_完整文档.md](docs/video-to-md_完整文档.md)，包含：
- 详细使用指南
- 技术原理与选型分析
- 故障排查
- 维护指南
- 迭代历史

## License

MIT
