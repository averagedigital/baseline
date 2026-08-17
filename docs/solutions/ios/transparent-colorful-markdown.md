# Transparent colorful Markdown in SwiftUI chat

## Problem

Markdown must keep the chat surface visible while giving headings and semantic spans clear color hierarchy.

## Symptoms

- Plain assistant text looks like a white document placed inside the chat.
- Headings, lists, and emphasis are visually flat.

## What did not work

- `Theme.gitHub` because its base text style sets an opaque background.
- Masking `MeshGradient` manually inside `TextRenderer`; `ImageRenderer` produced transparent glyphs.

## Root cause

MarkdownUI themes can attach background color directly to every text run. An explicit foreground color also prevents a SwiftUI `MeshGradient` foreground style from appearing.

## Solution

Build a transparent `Theme`, omit the base foreground color, and apply the iOS 18 `MeshGradient` directly to heading labels. Reserve solid colors and backgrounds for semantic elements such as emphasis, quotes, links, and code.

## Why it works

The chat owns the base foreground and background. Markdown styles only decorate the elements that need hierarchy.

## Verification

Render the view over a saturated test background and verify that most pixels remain visible. Render a heading separately and verify pixels from multiple gradient color regions.

## Prevention

Test visual theme behavior at the rendered-pixel boundary when adopting a prebuilt Markdown theme.

## Applies when

Rendering MarkdownUI content inside an existing SwiftUI chat or card surface on iOS 18 or newer.
