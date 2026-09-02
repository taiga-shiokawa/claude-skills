# Issue / コミットメッセージ / PR 本文のテンプレート

`/add-feature` の参照資料。Step 6-1・Step 11・Step 12 で使う。

各テンプレートを埋めた内容を**一時ファイルに書き出し**、そのパスをスクリプトに渡す
（`-BodyFile` / `-MessageFile`）。ヒアドキュメントを使わないので、引用符やエスケープの
崩れが起きない。一時ファイルの置き場所は `$env:TEMP\claude\add-feature\` を使い、
リポジトリ内には置かない（コミット対象に混ざるのを防ぐ）。

`<...>` はすべて実際の内容に置き換える。**置き換え漏れがあるとスクリプトが警告または中断する。**

本文はテンプレートの項目に**限定**する。要求や設計の全文をステアリングから転記せず、ステアリングディレクトリへの参照で済ませる（Issue・PR・完了報告で同じ説明を繰り返さない）。

---

## Issue 本文（Step 6-1 → `create-issue.ps1 -BodyFile`）

```markdown
## 概要

<何を追加・変更するか>

## 背景 / 目的

<なぜ必要か>

## 受け入れ条件

- [ ] <requirements.md の受け入れ条件>

## 影響範囲

<変更するコンポーネント・docs/ の更新有無>

## ステアリング

`.steering/<実際のディレクトリ名>/`
```

ラベルは `enhancement` / `bug` / `documentation` のいずれかを `-Label` で渡す。
リポジトリに存在しないラベルはスクリプトが自動で外す（新規作成はしない）。

---

## コミットメッセージ（Step 11 → `commit-and-push.ps1 -MessageFile`）

```
<type>: <変更内容の簡潔な要約>

<必要なら本文>

Closes #<issue-number>

Co-Authored-By: Claude <noreply@anthropic.com>
```

`<type>` と全体の形式は `development-guidelines.md` の Git 規約に従う。
規約が無ければ既存履歴に倣い Conventional Commits（`feat` / `fix` / `docs` / `refactor` / `test` / `chore`）。

`Co-Authored-By` 行の `<noreply@anthropic.com>` は**そのまま**残す（プレースホルダではない）。

---

## PR 本文（Step 12 → `open-pr.ps1 -BodyFile`）

```markdown
## 概要

<何を変更したか（1〜3行）>

## 変更内容

- <主な変更点>

## テスト / 検証

- lint: <結果>
- 型チェック: <結果>
- テスト: <結果>
- 動作検証: <実行したことと観測した挙動>

Closes #<issue-number>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

「テスト / 検証」には `quality-check.ps1` が返した JSON の実際の結果（PASS / FAIL / SKIP）と、
Step 10 の動作検証で観測した挙動を書く。SKIP したものは SKIP と明記する。

`Closes #<issue-number>` を必ず入れる。これが無いと `merge-pr.ps1` が
「PR に紐づく Issue が検出されませんでした」を返し、Issue が自動クローズされない。
