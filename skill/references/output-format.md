# Markdown Output Format

Generate **all three formats** in a single file for every video. Each format serves a different reading need — quick scan, logic deep-dive, and precise timestamp lookup.

## Principles

1. **Accuracy first** — preserve the speaker's intended meaning, not just keywords
2. **Three complementary lenses** — chapter scan / logic tree / time-coded detail
3. **Match source language** — Chinese video → Chinese output; English → English
4. **Use formatting for signal** — **bold** for core concepts, `code` for terms, > for key quotes
5. **Avoid filler** — every sentence should carry information; cut repetition and asides

## File path and naming

```bash
mkdir -p ./video-to-md
```

```
./video-to-md/YYYYMMDD_<topic_keyword>_视频整理.md   (Chinese)
./video-to-md/YYYYMMDD_<topic_keyword>_summary.md    (English)
```

Date is **today's date** (`date +%Y%m%d`).

---

## Full Template (three formats in one file)

```markdown
# <Video Title> — 视频内容详细整理

**频道**：<Channel> | **时长**：<Duration> | **发布**：<Upload Date>
**主题**：<1-line topic summary>
**来源**：<URL>

---

## TL;DR

<Video's single most important insight, distilled into 2-3 sentences. The one thing the viewer should remember.>

---

## 方式一：章节结构化

<!-- Follow the video's own chapter markers. Each chapter gets:
     - Core concept in **bold**
     - Supporting explanation (1-2 paragraphs)
     - Key quote in > blockquote
     - Comparison tables for A/B contrasts
     - Timestamps per chapter section
-->

### 一、<Chapter Title>（<timestamp>）

**<Core concept one sentence>**

<Explanation paragraph>

> <Memorable quote>

| 维度 | A | B |
|---|---|---|
| <dim> | <desc> | <desc> |

### 二、<Chapter Title>（<timestamp>）

...

---

### 章节总结

| 章节 | 核心要点 | 时间戳 |
|---|---|---|
| <chapter> | <gist> | <timestamp> |

---

## 方式二：分层大纲

<!-- Restructure the video's content as a nested logical tree.
     Top level: main arguments/themes (2-5 items)
     Second level: sub-points, evidence, examples
     Third level: details, data, quotes
     Preserves the speaker's reasoning chain independently of video order.
-->

### 核心论点 1：<Main Argument>

- **子论点 1.1**：<claim>
  - 论据：<evidence>
  - 案例：<example>
- **子论点 1.2**：<claim>
  - 细节：<detail>
  - 反例/边界：<counterpoint>

### 核心论点 2：<Main Argument>

- **子论点 2.1**：<claim>
  - ...

### 核心论点 3：<Main Argument>

- ...

---

### 大纲全景

```
1. <核心论点1>
   1.1 <子论点>
      ├ 论据
      └ 案例
   1.2 <子论点>
2. <核心论点2>
   ...
```

---

## 方式三：时间轴分段

<!-- Most detailed format. Break video into ~1-5 minute segments.
     Each segment: timestamp range + heading + detailed notes.
     Notes should be close to the original content — near-transcript quality
     but cleaned of filler words and false starts.
-->

### [00:00 – 02:30] <Segment Title>

<Detailed notes capturing what the speaker says, almost paragraph-by-paragraph. Preserve the original flow and examples. Use **bold** for key terms introduced in this segment.>

### [02:30 – 05:00] <Segment Title>

<Detailed notes...>

### [05:00 – 08:00] <Segment Title>

<Detailed notes...>

<!-- Continue for the full video, breaking at natural topic boundaries -->

---

### 时间轴索引

| 时间段 | 内容要点 | 关键术语 |
|---|---|---|
| 00:00-02:30 | <gist> | <terms> |
| 02:30-05:00 | <gist> | <terms> |
| 05:00-08:00 | <gist> | <terms> |
| ... | ... | ... |

---

## 全篇回顾

<One paragraph synthesis of the entire video. Pull together the core thread that runs through all the content.>

> <The single most powerful quote or takeaway from the video>
```

---

## Quality checklist

- [ ] Three formats all present: 章节结构化 / 分层大纲 / 时间轴分段
- [ ] TL;DR at top (2-3 sentences)
- [ ] Timestamps used in 方式一 and 方式三
- [ ] Core concepts **bolded** across all formats
- [ ] Comparison tables in 方式一 where A/B contrasts exist
- [ ] Blockquotes for strongest one-liners
- [ ] 时间轴索引 table at end of 方式三
- [ ] 全篇回顾 synthesis paragraph at the end
- [ ] `./video-to-md/` directory exists before saving
- [ ] Filename has `YYYYMMDD_` prefix from today's date
