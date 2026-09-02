# claude-skills

Claude Code の個人用スキル・スラッシュコマンド・サブエージェント定義のバックアップ。
`~/.claude/` 配下の `skills/` `commands/` `agents/` をそのままの構造で保管している。

## 構成

```
skills/     14件  Agent Skills（SKILL.md + references/scripts/assets）
commands/    6件  スラッシュコマンド定義（.md）
agents/      4件  サブエージェント定義（.md）
```

## 導入

別のPCやセットアップ直後の環境に戻す場合。

### コピーする

```powershell
git clone https://github.com/taiga-shiokawa/claude-skills.git
Copy-Item .\claude-skills\skills\*   "$env:USERPROFILE\.claude\skills\"   -Recurse
Copy-Item .\claude-skills\commands\* "$env:USERPROFILE\.claude\commands\" -Recurse
Copy-Item .\claude-skills\agents\*   "$env:USERPROFILE\.claude\agents\"   -Recurse
```

### リンクする（このリポジトリを編集しながら使う）

ジャンクションなら管理者権限なしで作れる。既存のディレクトリは先に退避すること。

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills" -Target "$PWD\claude-skills\skills"
```

## スキル一覧

| スキル | 用途 |
| --- | --- |
| `add-feature` | ステアリング作成 → Issue起票 → 実装 → テスト → レビュー → PR → main マージまでを自動実行する。承認はステアリング作成後の1回だけ。スラッシュコマンド専用（`disable-model-invocation`） |
| `atlas-register` | GOOYAのAI活用図鑑への事例登録。資料を Drive の図鑑フォルダへ格納し、事例マスタ（Sheets）へ1行追加する |
| `business-understanding` | 要件定義の前段の業務理解。固定5本のルールでヒアリングし、As-Is フロー・例外・課題一覧（頻度×時間）と改善機会を `docs/business-understanding.md` に残す |
| `daily-report` | 開発日誌（Word）の作成・更新と管理台帳（Excel）への1日1行の記録。書き込み先は SharePoint 同期フォルダ固定 |
| `decision-rules` | 業務理解から要件定義へ落とす際の意思決定。パレートの法則とシンプルルールでスコープ・優先順位を機械的に決め、決定記録として残す |
| `dev-docs` | ドキュメント駆動開発の標準ルール適用。永続的ドキュメント（`docs/`）とステアリングの初期化・監査・更新 |
| `drawio-shots` | 既存の drawio 図へスクリーンショットを自動配置。ファイル名規約でノードをマッチングし、base64 埋め込み＋点線接続まで行う |
| `gas-clone` | GAS プロジェクトの clasp クローン。スクリプトIDが不明でも URL 解析・ブラウザ・`clasp list` で自力特定を試みる |
| `gas-dev` | GAS 開発の一気通貫オーケストレータ。clone → 業務整理 → dev-docs → 機能開発 → push の5フェーズを状態検出して進める |
| `gas-push` | `clasp status` で点検してから `clasp push`。リモートを丸ごと上書きするため対象一覧の確認を必ず挟む |
| `hearing-sheet` | Drive のヒアリングシート雛形に沿ってヒアリングし、記入済みシートを Drive へ、`docs/idea.md` をローカルへ書き出す |
| `natural-japanese` | 日本語文書の執筆・校正とAI臭さの除去。**サードパーティ製**（下記参照） |
| `obsidian-log` | 会話を構造化サマリのノート1枚にまとめ、Obsidian 保管庫「AI Log」に保存する |
| `weekly-report` | エンジニアチームの週次報告書を Google ドキュメントとして作成し、Drive の指定フォルダへ `週次報告書_YYYYMMDD` で保存する |

## コマンド一覧

| コマンド | 用途 |
| --- | --- |
| `/fastapi-new` | FDE学習用の FastAPI プロジェクト（uv 構成）を新規作成 |
| `/fsos-dev` | FieldSpec OS の確定仕様からドキュメントを生成する仕様駆動フロー |
| `/init-idea` | アイデアの雛形（タイトル/背景/やりたいこと）を対話で埋め、`docs/ideas/initial-requirements.md` を作成 |
| `/python-new` | FDE学習用の汎用 Python プロジェクト（uv + src レイアウト）を新規作成 |
| `/review-docs` | `dev-docs` が生成した `docs/` 7ファイルと `CLAUDE.md` を review-docs サブエージェントでレビュー |
| `/understand-code` | コード理解の練習 |

## サブエージェント一覧

いずれも重い原文の読み込みを隔離コンテキストで肩代わりし、メインには要約だけを返す設計。

| エージェント | 役割 |
| --- | --- |
| `doc-writer` | `docs/` 配下や `CLAUDE.md` を1ファイルずつ生成・更新し、書いたパスと根拠だけを返す |
| `docs-digest` | `CLAUDE.md` と `docs/` を読み、実装に必要な前提（技術スタック・コマンド・規約）だけを圧縮して返す（読み取り専用） |
| `fsos-spec-fetcher` | FieldSpec OS の MCP から案件仕様を取得し、生の仕様はローカルキャッシュへ書き出して索引だけを返す |
| `review-docs` | `docs/` と `CLAUDE.md` の品質・整合性・網羅性をレビューし、指摘リストだけを返す（読み取り専用） |

## 前提ツール

スキルによって外部ツールを要求する。全部が必要なわけではない。

| ツール | 必要なスキル | 備考 |
| --- | --- | --- |
| `clasp` | `gas-clone` `gas-dev` `gas-push` | Google Apps Script CLI |
| `uv` | `natural-japanese` | lint スクリプトの依存（sudachipy 等）を PEP 723 のインラインメタデータから自動解決する |
| `gh` | `add-feature` | Issue 起票と PR 作成 |
| Python 3 | `drawio-shots` | 標準ライブラリのみで動く |
| Google Drive / スプレッドシート / Gmail コネクタ | `atlas-register` `weekly-report` `hearing-sheet` | |
| `fieldspec-os` MCP サーバ | `fsos-spec-fetcher` `/fsos-dev` | |
| SharePoint 同期フォルダ | `daily-report` | `MySharePoint - DailyReport` |
| Obsidian 保管庫 | `obsidian-log` | `~/Documents/AI Log` |

## サードパーティのスキル

`skills/natural-japanese` は [coji/natural-japanese](https://github.com/coji/natural-japanese) を取り込んだもの。

- ライセンス: MIT（`skills/natural-japanese/LICENSE`）
- 取り込み時点: commit `0f1cc1c`（2026-09-02 時点の最新）
- 上流の更新を取り込む場合は `npx skills add coji/natural-japanese` で入れ直すか、上流の `skills/natural-japanese/` を再コピーする

`scripts/semantic.py`（`score exp` モードの深層検出）は torch + sentence-transformers と約1GBのモデルを追加で要求する opt-in 機能。初回実行時に uv が取得する。

## 注意

- 各スキルには Google Drive のフォルダID・スプレッドシートIDといった環境固有の値が直接書かれている（`atlas-register` と `weekly-report` の「設定」表）。**Private リポジトリ前提**であり、公開しないこと。
- 認証情報・APIキー・トークンは含まれていない。
