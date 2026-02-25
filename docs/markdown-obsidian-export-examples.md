# Markdown & Obsidian Export Examples

This document shows example outputs from the new Markdown and Obsidian export formats.

## Standard Markdown Export

```markdown
# 📊 time.md Data Export

**Generated:** 2026-02-25T09:30:00-04:00
**Date Range:** 2026-02-18 → 2026-02-25
**Granularity:** day

---

## Table of Contents
- [📈 Summary](#summary)
- [📱 Top Apps](#top-apps)
- [📊 Trends](#trends)

---

## 📈 Summary

| metric              | value    |
|---------------------|----------|
| total_seconds       | 25200.00 |
| average_daily_seconds | 3600.00  |
| focus_blocks        | 12       |

---

## 📱 Top Apps

| app_name | total_seconds | session_count |
|----------|---------------|---------------|
| Safari   | 7200.000      | 45            |
| Xcode    | 5400.000      | 23            |
| Terminal | 3600.000      | 67            |
| Slack    | 2700.000      | 89            |
| Figma    | 1800.000      | 12            |

---

*⏱️ Exported by [time.md](https://timeprint.app)*
```

## Obsidian Export (with Frontmatter)

```markdown
---
title: "time.md Data Export"
date: 2026-02-25
type: screentime-export
total_hours: 7.00
total_minutes: 420
created: 2026-02-25T09:30:00
modified: 2026-02-25T09:30:00
top_apps:
  - "Safari"
  - "Xcode"
  - "Terminal"
  - "Slack"
  - "Figma"
tags:
  - timeprint
  - screentime
filters: "date_range=2026-02-18..2026-02-25; granularity=day"
---

# 📊 time.md Data Export

| Property | Value |
|----------|-------|
| **Generated** | [[2026-02-25]] |
| **Date Range** | [[2026-02-18]] → [[2026-02-25]] |
| **Total Time** | 7.0 hours |

#timeprint #screentime

---

> [!summary] Sections
> - [📈 Summary](#summary)
> - [📱 Top Apps](#top-apps)
> - [📊 Trends](#trends)

## 📈 Summary

| metric              | value    |
|---------------------|----------|
| total_seconds       | 25200.00 |
| average_daily_seconds | 3600.00  |
| focus_blocks        | 12       |

## 📱 Top Apps

| app_name                   | total_seconds | session_count |
|----------------------------|---------------|---------------|
| [[Apps/Safari\|Safari]]    | 7200.000      | 45            |
| [[Apps/Xcode\|Xcode]]      | 5400.000      | 23            |
| [[Apps/Terminal\|Terminal]]| 3600.000      | 67            |
| [[Apps/Slack\|Slack]]      | 2700.000      | 89            |
| [[Apps/Figma\|Figma]]      | 1800.000      | 12            |

---

## 🔗 Related

- Daily Note: [[2026-02-25]]
- Top Apps:
  - [[Apps/Safari|Safari]]
  - [[Apps/Xcode|Xcode]]
  - [[Apps/Terminal|Terminal]]
  - [[Apps/Slack|Slack]]
  - [[Apps/Figma|Figma]]

*⏱️ Exported by [time.md](https://timeprint.app)*
```

## Features

### Markdown Format
- Clean, readable tables (GitHub Flavored Markdown)
- Optional table of contents
- Section emojis
- Horizontal rule separators
- Timestamp format options

### Obsidian Format
- **YAML Frontmatter** with:
  - Title, date, type
  - Total hours/minutes
  - Top apps list
  - Custom tags
  - Dataview-compatible fields
- **Wiki Links** (`[[...]]`) for:
  - Daily notes (dates)
  - App notes (organized in configurable folder)
- **Callouts** for table of contents
- **Backlinks** section for related content
- **Tags** inline and in frontmatter

## Configuration Options

### Markdown Options
| Option | Description | Default |
|--------|-------------|---------|
| Table Style | GFM, Simple, or HTML | GFM |
| Heading Style | ATX (#) or Setext (underline) | ATX |
| Include TOC | Table of contents | Yes |
| Include Emoji | Section emojis | Yes |
| Horizontal Rules | Section separators | Yes |

### Obsidian Options
| Option | Description | Default |
|--------|-------------|---------|
| Frontmatter Style | YAML (---) or TOML (+++) | YAML |
| App Notes Folder | Folder path for app links | "Apps" |
| Daily Note Format | Date format for links | yyyy-MM-dd |
| Include Wiki Links | Enable [[...]] linking | Yes |
| Include Tags | Add hashtag tags | Yes |
| Dataview Compatible | Add created/modified fields | Yes |
| Create Backlinks | Related section | Yes |
