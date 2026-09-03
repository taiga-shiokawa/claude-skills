# デザイン仕様 — GOOYAのAI活用図鑑 PowerPoint

図鑑サイト（gooya-ai-atlas の `src/index.html`）の CSS カスタムプロパティを PowerPoint に翻訳した仕様。サイト側の色を変えたときは、ここと `scripts/atlas_theme.py` の COLORS を同時に更新する。

## 配色 — サイトのトークンと1対1で対応させる

| 用途 | 名前 | HEX | サイト側トークン |
|---|---|---|---|
| ブランド緑（バッジ・数字・アイコン） | BRAND | 6BBF3F | --c-brand |
| 濃い緑（ピル文字・強調見出し） | BRAND_DARK | 55A02F | --c-brand-dark |
| 淡い緑（ピル背景・プロンプト枠） | BRAND_SOFT | EAF7E1 | --c-brand-soft |
| ごく淡い緑（表紙背景） | BRAND_TINT | F4FBEF | --c-brand-tint |
| 本文テキスト | TEXT | 1E2A22 | --c-text |
| 補足テキスト | TEXT_SUB | 5E6E64 | --c-text-sub |
| 出典・キャプション | TEXT_MUTE | 8A9990 | --c-text-mute |
| カード枠線 | BORDER | E3E9E3 | --c-border |
| カード背景 | SURFACE_ALT | F7FAF7 | --c-surface-alt |
| 注意・警告 | DANGER | C2453B | --c-danger |
| ページ背景 | WHITE | FFFFFF | --c-bg |

**面積の目安**: 白地 7、淡緑（カード・ピル）2、ブランド緑 1。緑を増やすほど図鑑らしさは下がる（サイト自体が白主体のデザインのため）。

## タイポグラフィ

フォントは全要素 **游ゴシック（Yu Gothic）**。日本語 Windows の Office に標準搭載で、サイトのフォントスタック（Hiragino → Yu Gothic → Meiryo）の Windows 側実体に一致する。`atlas_theme.py` の `set_text()` が日本語（East Asian）と英数（Latin)の両方に游ゴシックを設定する。

| 要素 | サイズ | 太さ | 色 |
|---|---|---|---|
| 表紙タイトル | 36–40pt | Bold | TEXT（キーワード1語だけ BRAND_DARK 可） |
| 表紙サブタイトル | 16–18pt | Regular | TEXT_SUB |
| スライドタイトル | 22–26pt | Bold | TEXT |
| カード見出し・小見出し | 14–16pt | Bold | TEXT |
| 本文 | 12–14pt | Regular | TEXT |
| 補足・注記 | 10.5–12pt | Regular | TEXT_SUB |
| 出典（フッター） | 9pt | Regular | TEXT_MUTE |
| ピル内テキスト | 10.5–11pt | Bold | BRAND_DARK |
| 数字バッジ | 14–18pt | Bold | WHITE |

## 部品（atlas_theme.py のヘルパー対応）

- **ピルバッジ** `add_pill()` — 完全角丸、BRAND_SOFT 背景 + BRAND_DARK 太字。カテゴリ表示・タグに使う。枠線なし。アウトライン版（白背景 + BORDER 枠 + TEXT_SUB 文字）は補助情報（連携方式など）用。
- **数字バッジ** `add_number_badge()` — BRAND 塗りの正円 + 白太字数字。手順・項番に使う。
- **アイコンバッジ** `add_icon_badge()` — BRAND 塗りの正円 + 白抜き PNG アイコン。既存資料を再デザインするとき、元のアイコン画像（多くは白一色で色付き円に載っている）を python-pptx の `sh.image.blob` で抜き出し、円の色だけブランド緑に差し替えれば意匠が揃う。カード見出しの左に直径 0.36〜0.44 インチで置くのが基準。
- **カード** `add_card()` — 角丸 8〜12pt 相当、SURFACE_ALT 塗り + BORDER 1pt 枠、影なし。本文ブロックの器。
- **プロンプトカード** — `add_card()` の塗りを BRAND_SOFT にした変種。「そのままコピーして使う文面」を入れる専用。ラベル（例:「プロンプト例（そのままコピーして利用）」）を BRAND_DARK 太字で先頭に置く。
- **箇条書き** `add_bullets()` — 行頭記号「•」を BRAND 色で付ける。記号を本文に手打ちしない。
- **矢印・フロー** — 細い BRAND 色のシェブロン（MSO_SHAPE.CHEVRON）または「→」テキスト。太い塗り矢印は使わない。

## レイアウトレシピ

スライドサイズは 16:9（13.333 × 7.5 インチ）。余白は上下左右 0.5 インチ以上、ブロック間 0.25〜0.35 インチ。

### 表紙
BRAND_TINT の全面背景。中央に、上から順に「小ピル（資料種別）→ タイトル → サブタイトル → タグのピル列」。ピル列はサイトのタグ表示の再現で、5〜7 個まで。

### 本文スライド（標準）
白背景。左上にカテゴリのピル、その下にタイトル行（必要なら数字バッジ + タイトル）。本文はカード 1〜3 枚で構成し、素のテキストを背景に直置きしない。出典は左下に 9pt TEXT_MUTE。

### 一覧・マップ
項目ごとに小カードを並べる（2×3 グリッドまで）。カード内は「見出し（太字）＋ 説明 1〜2 行」。カード間の矢印はシェブロンで。

### まとめ
数字バッジ + 1 行メッセージの縦積み。最大 5 行。

## テキスト抽出スクリプトの例（再デザイン時）

```python
import json
from pptx import Presentation
prs = Presentation(SRC)
data = []
for i, s in enumerate(prs.slides, 1):
    shapes = []
    for sh in s.shapes:
        if sh.has_text_frame:
            paras = ["".join(r.text for r in p.runs) for p in sh.text_frame.paragraphs]
            shapes.append({"name": sh.name, "paras": paras})
        else:
            shapes.append({"name": sh.name, "type": str(sh.shape_type)})
    data.append({"slide": i, "shapes": shapes})
json.dump(data, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
```
