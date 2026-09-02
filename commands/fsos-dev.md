---
description: FieldSpec OS の MCP から案件仕様を取得し、それを唯一の情報源として README.md / CLAUDE.md / 永続的ドキュメント（docs/ 7点）を生成する（dev-docs の MCP 連携版）
argument-hint: [案件名 or projectId]（省略時は list_projects で一覧提示）
---

# fsos-dev：FieldSpec OS 仕様駆動ドキュメント生成

`/dev-docs` の改良版。ヒアリングや手入力で情報源を集める代わりに、**FieldSpec OS の MCP（`fieldspec-os`）から
案件の確定済み仕様を取得し、それを「唯一の情報源（SSOT）」として** README.md / CLAUDE.md / 永続的ドキュメント
（`docs/` の7ファイル）を生成する。仕様駆動開発（要求・設計・実装・検証をつなぐ変更管理された情報源）を、
実装リポジトリのドキュメントへ橋渡しするのが目的。

引数: `$ARGUMENTS`

- **引数なし** → `list_projects` で案件一覧を提示し、どの案件のドキュメントを生成するかユーザーに選ばせる。
- **案件名 or projectId** → その案件を特定して生成フローに入る。

## 前提：MCP 接続の確認

このスキルは `fieldspec-os` MCP サーバ（tools: `list_projects` / `get_project_status` / `get_project_spec`）に依存する。

- MCP は read-only。ここでは**仕様を読むだけ**で、FieldSpec OS 側の成果物は一切書き換えない。
- 接続確認は `fsos-spec-fetcher` サブエージェント側で行う（ステップ 0）。未接続と返ってきたら、FieldSpec OS リポジトリの
  README「FieldSpec OS MCP サーバ」節（ユーザースコープ登録手順、PAT 発行）を案内し、中止する。

## ステップ 0：案件の特定と仕様取得（`fsos-spec-fetcher` に委譲）

**MCP 呼び出しはメインで行わない。** `get_project_spec` の返却物には `hearingSheetMarkdown`（ヒアリングシート全文）と
`requirementsDocMarkdown`（要件定義書本文）が含まれ、そのままメインコンテキストに載せると、この後の docs 7点生成に
使える余地が無くなる。`fsos-spec-fetcher` サブエージェントに取得させ、**生の仕様はローカルのキャッシュファイルに
逃がして、メインは索引だけを受け取る**。

1. `fsos-spec-fetcher` を起動し、引数（案件名 or `projectId`）を渡す。
2. サブエージェントが返すもの:
   - 確定した `projectId` / 顧客名 / 案件名 / `generatedAt`
   - **キャッシュファイルのパス**（`.steering/.cache/fsos-spec-<projectId>.json`）— 以降のステップで各生成エージェントに渡す
   - フィールド索引（有無と件数）、FR / AC / Q の ID 一覧、見出し一覧
   - 充足チェック結果
3. **案件が一意に決まらなかった場合**は、サブエージェントが候補一覧だけを返して終了する。
   その一覧をユーザーに提示して選ばせ、確定した `projectId` で `fsos-spec-fetcher` を再度起動する
   （サブエージェントはユーザーに質問できないため、選択はメインの責務）。
4. **充足チェックが ⚠️（`requirements` や `acceptanceCriteria` が空）の場合**は、その案件は 02_要件定義まで未生成。
   ユーザーに知らせ、「ヒアリング/業務設計だけで下書きするか」「FieldSpec OS 側で要件定義を生成してから
   再実行するか」を確認する（薄い仕様から docs を捏造しない）。この判断もメインが行う。

以降、**仕様の参照はすべてキャッシュファイル経由**とする。メインがキャッシュを `Read` することはない。

`get_project_spec` の出力フィールド（情報源。キャッシュ JSON のキーと同じ）:

| フィールド | 内容 |
| --- | --- |
| `hearingSheetMarkdown` | ヒアリングシート全文（顧客の一次情報：背景・期待成果・業務フロー・課題・要望・決定事項・制約） |
| `businessDesignSummary` | 業務課題整理（BIZ-xxx）・根本原因分析・As-Is / To-Be 業務フロー |
| `requirements[]` | 要求（FR-xxx：分類・内容・背景根拠・優先度(MoSCoW)・対応AC/論点ID） |
| `acceptanceCriteria[]` | 受け入れ条件（AC-xxx：Given/When/Then・検証方法） |
| `openQuestions[]` | 未確定論点（Q-xxx：論点・選択肢・推奨案・確認先） |
| `requirementsDocMarkdown` | 要件定義書本文（背景・スコープ・用語・機能/非機能要件・制約） |

## ステップ 1：ローカルリポジトリの把握（`Explore` に委譲）

生成する docs は「**何を作るか**（＝MCP の仕様）」と「**どう作るか**（＝このリポジトリの実態）」の両方を反映する。
後者の調査は、組み込みの **`Explore` サブエージェント**に委譲する（`/dev-docs` 手順 1.5 と同じ）。返させるもの:

- 言語・フレームワーク・主要ライブラリと**バージョン**（`package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` 等の実値）
- build / 開発サーバ / lint / 型チェック / テスト / フォーマットの**実コマンド**（存在しないものは「なし」と明記させる）
- ディレクトリ構成の要約（深さ2〜3）
- 既存の `docs/` `CLAUDE.md` `README.md` の有無

この結果を「リポジトリ実態サマリ」として、以降の `doc-writer` 起動時に毎回渡す。

- 仕様（ヒアリング §10 既存ツール・§13 技術決定）とリポジトリ実態が食い違う場合は、リポジトリ実態を優先し、
  差異はユーザーに確認する。まだ空のリポジトリなら、仕様＋dev-docs 推奨構成から初期構成を提案する。

## ステップ 2：永続的ドキュメント（`docs/` 7点）の生成

**上書き防止**: `docs/` に既存ファイルがあれば、いきなり上書きしない。既存を列挙し「不足分のみ / 作り直し / 中止」を確認する。

`mkdir -p docs .steering` の後、次の順で作成する。**各ファイルの執筆は `doc-writer` サブエージェントに委譲する。**

`doc-writer` 起動時に渡すもの:

- 生成対象ファイルのパス
- **キャッシュファイルのパス**（ステップ 0）と、下表の「主な情報源」に挙がっている**フィールド名**（全フィールドを舐めさせない）
- ステップ 1 のリポジトリ実態サマリ
- **既に確定した先行ドキュメントの決定事項**（前回の `doc-writer` が返した「次のファイルへの引き継ぎ事項」をそのまま渡す）

**1ファイルごとに作成→承認を得てから次へ**進む（`/add-feature` 等でまとめて承認する運用に合わせてもよい）。
承認はメインが取り、`doc-writer` が返した要約とファイルパスを提示してユーザーに実ファイルを確認してもらう。
**7ファイルを並列生成しない**（先行の決定事項に後続が従う必要があるため、並列にすると整合性が壊れる）。
`doc-writer` が「矛盾の検知」を返したら、次に進む前にユーザーに提示して解消する。

各ファイルは下表の情報源から生成する。

| # | ファイル | 主な情報源（get_project_spec のフィールド ＋ リポジトリ実態） |
| --- | --- | --- |
| 1 | `product-requirements.md` | `hearingSheetMarkdown`（背景・期待成果・想定ユーザー・課題・要望）／`businessDesignSummary`（BIZ 課題）／`requirements`（機能・非機能要件）／`acceptanceCriteria`（受け入れ条件）／`openQuestions`（未確定論点） |
| 2 | `functional-design.md` | `requirements`（機能要件）／`businessDesignSummary`（As-Is/To-Be＝業務フロー図・ユースケース）／`hearingSheetMarkdown` §8（ユースケース）／`requirementsDocMarkdown`。アーキテクチャ・データモデル・画面はアーキ原則に沿って設計 |
| 3 | `architecture.md` | `hearingSheetMarkdown` §10（既存ツール）・§13（技術決定：例「レイヤード採用」）／`requirements` 非機能／`requirementsDocMarkdown` §6（制約・前提）／**リポジトリ実態**（スタック・バージョン） |
| 4 | `repository-structure.md` | architecture の決定＋リポジトリ実態＋dev-docs 推奨構成（ドメイン駆動 × レイヤード） |
| 5 | `development-guidelines.md` | リポジトリ実態（Lint/テスト/フォーマット/Git）＋dev-docs のアーキテクチャ原則の運用規約 |
| 6 | `glossary.md` | `requirementsDocMarkdown` §3（用語）／`hearingSheetMarkdown`（ドメイン用語）／ID 規約（BIZ/FR/AC/Q） |
| 7 | `development-roadmap.md` | `hearingSheetMarkdown`（期限・MVP 範囲）／`requirements` の優先度（MoSCoW）／`openQuestions`（未決の解消順） |

各ドキュメントの章立て・粒度は `/dev-docs` の「永続的ドキュメント」定義に従う（`doc-writer` が自分で
`~/.claude/skills/dev-docs/references/permanent-docs-chapters.md` を読んで適用する。このパスを
`doc-writer` に必ず渡すこと）。

## ステップ 2.5：ドキュメント横断レビュー（必須）

7ファイルが揃ったら、**`/review-docs` を必ず実行する。** 1ファイルずつ逐次生成しているため、単体では整合していても
ドキュメント間の不整合（技術スタックの食い違い、FR → 設計のトレーサビリティ欠如、用語の表記ゆれ）が残りうる。

- **Critical は実装に入る前に必ず修正する。** 修正は `doc-writer` に該当ファイルを渡して行い、修正後にもう一度かける。
- 根拠 ID（BIZ / FR / AC / Q）の欠落や、`（要確認）` の残存も併せて確認する。

## ステップ 3：CLAUDE.md の生成

CLAUDE.md を作成（既存なら該当セクションを追記）。`doc-writer` に委譲してよいが、その場合は
**「記載内容を次の4項目に限定する」制約を明示的に渡す**こと。本スキルや dev-docs の全文を写さない:

1. **ステアリング規則の要約**：`.steering/[YYYYMMDD]-[開発タイトル]/` に requirements/design/tasklist を作ること、命名規則。
2. **プロジェクト固有情報**：確定した技術スタック、ビルド/テスト/lint コマンド、仮想環境の有効化。
3. **仕様の出所（重要）**：「本プロジェクトの仕様の真の情報源は FieldSpec OS の案件
   `<projectId>`（顧客: <…> / 案件: <…>）であり、`fieldspec-os` MCP の `get_project_spec` で参照・再取得する」旨を明記。
4. **プロセス参照**：「開発プロセスの詳細は `/dev-docs`、仕様の再取得は `/fsos-dev` に従う」の1〜2行。

## ステップ 4：README.md の生成

`product-requirements.md` と `architecture.md` を基に、プロダクト概要・目的・主要機能・セットアップ/実行手順・
仕様の参照先（FieldSpec OS 案件 id と MCP）を README にまとめる。`doc-writer` に委譲してよい
（情報源として上記2ファイルのパスとリポジトリ実態サマリを渡す）。

## ステップ 5：ステアリング初期化と実装

`/dev-docs` の「初回セットアップ」（`~/.claude/skills/dev-docs/references/init-setup.md`）に準じ、
`.steering/<YYYYMMDD>-initial-implementation/` に requirements/design/tasklist を作成する。
ディレクトリ作成は `~/.claude/skills/dev-docs/scripts/new-steering.ps1 -Title initial-implementation`
を使う（実行時日付を解決する）。以降の実装は tasklist に従う。

## 生成ルール（品質・トレーサビリティ）

- **SSOT はあくまで FieldSpec OS の仕様**。docs には根拠の ID（BIZ-xxx / FR-xxx / AC-xxx / Q-xxx）を保持し、
  仕様のどの項目に由来するか辿れるようにする（例：機能要件に対応 FR-ID、受け入れ条件に AC-ID を併記）。
- **キャッシュファイルは SSOT のローカル写しに過ぎない**。`generatedAt` で鮮度を確認し、FieldSpec OS 側が更新されたら
  `fsos-spec-fetcher` を再実行してキャッシュを取り直す。キャッシュを直接編集しない。顧客の一次情報を含むため
  `.gitignore` で `.steering/.cache/` を除外する（`fsos-spec-fetcher` が対応済み）。
- **仕様の原文をメインコンテキストに読み込まない**（`/dev-docs`「サブエージェント運用方針」）。取得は
  `fsos-spec-fetcher`、参照は各 `doc-writer` がキャッシュから行う。
- **捏造しない**。仕様に無い数値・固有名詞を作らない。未確定な点は `openQuestions`（Q-xxx）を「未確定論点」として
  そのまま docs に転記し、「（要確認）」と明記する。ヒアリングの「（要確認）」も踏襲する。
- **段階承認**：各永続ドキュメントは作成→承認→次、を守る（`/add-feature` 経由なら一括承認でよい）。
- **アーキテクチャ原則**：`architecture.md` / `functional-design.md` / `repository-structure.md` /
  `development-guidelines.md` は、`/dev-docs` の「アーキテクチャ原則」
  （`~/.claude/skills/dev-docs/references/architecture-principles.md`。ドメイン分割・単一責任・一方向依存・
  疎結合・依存性逆転）を**文書上で担保**する。責務・依存方向・ポート定義場所・変換規約まで落とし込む。
- **図表**：ER 図・ユースケース図・業務フロー図・画面遷移図は関連する永続ドキュメント内に Mermaid で記載
  （As-Is/To-Be は `businessDesignSummary` を基にフロー図化）。独立した diagrams フォルダは作らない。
- **再生成**：仕様が更新されたら `get_project_spec` を再取得し、影響する docs を更新する（`generatedAt` で鮮度確認）。
- コード変更後は必ず lint・型チェック・関連テストを実施する。

## 完了時の報告

生成/更新したファイル一覧、参照した案件（id・顧客・案件名・`generatedAt`）、仕様が薄く「（要確認）」で埋めた箇所、
未解決の `openQuestions`、ステップ 2.5 のレビュー結果を要約して報告する。
各 `doc-writer` が返した「要確認箇所」を集約して一覧にすること。
