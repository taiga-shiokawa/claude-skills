---
name: add-feature
description: docs/ の前提取得と影響分析をサブエージェントに委譲したうえで、ステアリングファイル規則に従って「ステアリング作成→Issue起票→実装→テスト→検証→レビュー→PR作成→mainマージ」までを自動実行する（ステアリング作成後に1回だけ承認）
argument-hint: <開発タイトル または 追加したい機能の説明>
disable-model-invocation: true
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/*.ps1 *)
  - PowerShell(${CLAUDE_SKILL_DIR}/scripts/*.ps1 *)
---

# 機能追加の自動実行（add-feature）

`/dev-docs` の「機能追加・修正時の手順」を、**ステアリングファイル作成後の1回の承認**を挟んで全工程自動で回す。
CLAUDE.md と `docs/` 配下の永続的ドキュメントを真とし、CLAUDE.md に記載されたステアリングファイル規則
（`.steering/[YYYYMMDD]-[開発タイトル]/` に `requirements.md` / `design.md` / `tasklist.md`）に従う。

全体の流れ:

```
[docs-digest] 前提取得 → [Explore] 影響分析 → ステアリング3ファイル作成 → 【承認ゲート】
  → GitHub Issue 起票 → 作業ブランチ作成 → 実装 → lint/型/[test-writer]テスト
  → [general-purpose] 動作検証 → [code-reviewer] PR前レビュー
  → commit & push → PR 作成 → main へマージ → 完了報告
```

`[…]` はサブエージェントへの委譲。**原文の重い読み込み・冗長な実行ログはメインに載せない**（詳細は `/dev-docs`「サブエージェント運用方針」）。承認ゲート・実装本体・git/gh 操作はメインが行う。

引数: `$ARGUMENTS`

- 引数 = 追加・変更したい機能の説明、または `<開発タイトル>`（例: `add-tag-feature`、`タグ機能を追加`）
- 引数なし → 「どんな機能を追加するか」をユーザーに尋ねてから開始する

## 同梱スクリプト

git / gh の操作は同梱の PowerShell スクリプトで行う。**インラインでシェルを組み立てない。**
スクリプトが実行時日付の解決・ガード判定・結果の JSON 化を担い、生出力がメインに載るのを防ぐ。

| スクリプト | 用途 | Step |
| --- | --- | --- |
| `${CLAUDE_SKILL_DIR}/scripts/preflight.ps1` | gh / git の状態を1つの JSON で取得 | 0 |
| `${CLAUDE_SKILL_DIR}/scripts/new-steering.ps1 -Title <t>` | ステアリングディレクトリ作成 | 3 |
| `${CLAUDE_SKILL_DIR}/scripts/create-issue.ps1 -Title <t> -BodyFile <p> [-Label <l>]` | Issue 起票 | 6-1 |
| `${CLAUDE_SKILL_DIR}/scripts/new-branch.ps1 -Prefix <p> -Title <t>` | 作業ブランチ作成 | 6-2 |
| `${CLAUDE_SKILL_DIR}/scripts/quality-check.ps1` | lint / 型 / テストを自動判別して実行 | 9 |
| `${CLAUDE_SKILL_DIR}/scripts/commit-and-push.ps1 -MessageFile <p>` | commit & push | 11 |
| `${CLAUDE_SKILL_DIR}/scripts/open-pr.ps1 -Title <t> -BodyFile <p>` | PR 作成 | 12 |
| `${CLAUDE_SKILL_DIR}/scripts/merge-pr.ps1 -QualityGreen -ReviewClean` | ガード通過時のみマージ | 12 |

Issue / コミットメッセージ / PR の本文テンプレートは `references/body-templates.md`（Step 6・11・12 で読む）。

---

## Step 0: 前提チェック

- `CLAUDE.md` と `docs/` が存在するか確認する（`Glob` で `docs/**/*.md` と `CLAUDE.md`）。
  - どちらも無い／`docs/` が未生成 → **中断**し、「先に `/dev-docs init` で永続的ドキュメントを整備してください」と案内する。
- `preflight.ps1` を実行し、返った JSON で判断する:
  - `ghInstalled` / `ghAuthed` / `isGitHub` のいずれかが false → Issue・PR の工程はスキップし、その旨を Step 5 の提示に明記する（実装自体は続行）。
  - `dirty` が true → `dirtyFiles` をユーザーに知らせ、stash / commit するか確認してから進む。
  - `defaultBranch` が `main` 以外なら、以降のスクリプト呼び出しで `-BaseBranch` / `-Base` にその名前を渡す。
- 引数が空なら、追加したい機能の内容をユーザーに確認する。

## Step 1: コンテキスト読み込み（`docs-digest` に委譲）

**`docs-digest` サブエージェントを起動し、実装前提ダイジェストだけを受け取る。**

- 依頼内容: 「`CLAUDE.md` と `docs/` 配下の永続的ドキュメント一式、`docs/ideas/initial-requirements.md` を読み、実装前提ダイジェストを返すこと」。今回追加する機能の説明を**フォーカスとして必ず渡す**（用語・要求の抜粋がその機能に絞られる）。
- 受け取るもの: 確定技術スタック / ビルド・テスト・lint・型チェックの実コマンド / **Git 規約（ブランチ命名・コミットメッセージ形式）** / コーディング・命名・スタイル規約 / ファイル配置ルールと依存方向の制約 / テスト規約 / 関係する用語 / 関係する要求・設計 / 各項目の出典。

**メインで `docs/` の原文を読み込まないこと。** 実装フェーズのためにコンテキストを温存するのが目的であり、原文を読み直したら委譲の意味が消える。後で細部が必要になったら、ダイジェストの出典ポインタ（`ファイル > セクション`）を頼りに**その箇所だけ**を `Read` する。出典が不明な場合の所有文書の目安: 要求・受け入れ条件→product-requirements / 振る舞い・API・データ→functional-design / 技術・境界・依存→architecture / 配置→repository-structure / コマンド・テスト・Git→development-guidelines / 用語→glossary / フェーズ→roadmap。

ただし `CLAUDE.md` は**メインでも直接読む**（短く、毎セッション読み込まれる前提のファイルであり、規則の解釈を委譲すべきでないため）:

- **ここに書かれたステアリングファイル規則を最優先で順守する**（ディレクトリ命名、作成するファイル、各種規約）。CLAUDE.md の規則が以下の手順と食い違う場合は CLAUDE.md を優先。**ただし承認の粒度は例外**: CLAUDE.md や dev-docs に「1ファイルごとに承認」とあっても、本スキルではステアリング3ファイルを一括作成し、承認は Step 5 の1回にまとめる（これは dev-docs が認める例外である）。

`docs-digest` が「ドキュメント未整備」を返した場合は Step 0 の判断に戻る（`/dev-docs init` を案内する）。

## Step 2: 影響分析（`Explore` に委譲）

既存コードへの影響範囲の洗い出しは、組み込みの **`Explore` サブエージェント**に委譲する。**メインで `Glob`/`Grep`/`Read` を広く回さない。**

- 探索範囲の指定: 通常は "medium"。スコープが不明・複数モジュールに跨りそうなら "very thorough"。
- 依頼時に渡すもの: 追加する機能の説明、Step 1 のダイジェストから得た**ファイル配置ルールと依存方向の制約**。
- 返させるもの（これだけ）:
  1. 変更・追加が必要なファイルと `file:line`
  2. 踏襲すべき既存の実装パターン（同種の機能が既にどう書かれているか）
  3. **再利用できる既存の関数・ユーティリティ・型**（新規作成の前に必ず既存を探させる）
  4. 見落としやすい波及先（型定義・テスト・設定・マイグレーション等）

そのうえでメインが判定する:

- 今回の機能が**永続的ドキュメント（`docs/`）に影響するか**。更新するのは**承認後も残る製品契約・基本設計が変わる場合だけ**。既存仕様どおりのバグ修正・内部リファクタリング・テスト追加・局所的な実装詳細では更新しない。
- 影響する場合は所有文書を1つに定め（他文書へ同じ説明を複製しない）、「どのファイルをどう更新するか」を控えておく（実際の更新は承認後の Step 7 で行う）。

## Step 3: ステアリングディレクトリ作成

開発タイトルを決める（引数から。日本語説明なら短い英語ケバブケースに変換。例: `タグ機能を追加` → `add-tag-feature`）。
このタイトルはステアリングディレクトリ名・ブランチ名・Issue/PR タイトルで一貫して使う。

```
${CLAUDE_SKILL_DIR}/scripts/new-steering.ps1 -Title <開発タイトル>
```

`CREATED<TAB><path>` を返す。`EXISTS` が返った場合は上書きせず、別のタイトルにする。
CLAUDE.md にこれと異なる命名規則があればそれに従う。

## Step 4: ステアリング3ファイルを一括作成

`.steering/[YYYYMMDD]-[開発タイトル]/` に、dev-docs 規約に沿って3ファイルを作成する（ここでは承認を取らず一括で作る）:

1. **requirements.md** — 今回の要求内容 / ユーザーストーリー / 受け入れ条件 / 制約事項
2. **design.md** — 実装アプローチ / 変更するコンポーネント / データ構造の変更 / 影響範囲の分析（Step 2 の `docs/` 更新方針もここに明記）
3. **tasklist.md** — 具体的な実装タスク（チェックボックス形式）/ 完了条件。**テスト作成と動作検証もタスクに含める。**

**3ファイルで文章を使い回さない。** 要求は requirements.md にだけ書き design.md から参照する。設計説明を tasklist.md へ転記しない。
要求・設計は `docs/` の永続的ドキュメントおよび North Star と矛盾しないようにする。

## Step 5: 【承認ゲート】← ここだけ人が確認

実装に入る前に、ユーザーへ次を**簡潔に**提示し、承認を求めて**いったん停止する**:

- 開発タイトルとステアリングディレクトリのパス
- requirements / design / tasklist の要点（各2〜4行程度のサマリ。全文は貼らない）
- 影響する `docs/` 更新の有無と対象ファイル
- 主要な実装タスク一覧
- **GitHub 連携の実行内容**（承認はここで一括して得る）:
  - 起票する Issue のタイトル・付けるラベル
  - 作成する作業ブランチ名
  - 実装後に動作検証とコードレビュー（`code-reviewer` があれば）を行うこと
  - 完了後に **PR を作成し、green なら `main` へマージする**（マージ方式・ブランチ削除の有無も明記）

「この内容で実装に進んでよいか？（Issue 起票 → 実装 → PR → main マージまで自動実行します）」と確認する。
修正要望があればステアリングを直して再提示する。
**承認が得られるまで Step 6 以降に進まない。** この承認をもって、Issue 起票・PR 作成・main マージの実行許可とみなす。
**承認は提示した範囲にだけ有効。** 提示していない外部操作や破壊的操作が途中で必要になった場合は、承認を流用せず停止して確認する（「停止条件」参照）。GitHub 連携が使えない場合はスキップする工程を提示に明記する。

---
（以下、承認後に自動実行）

## Step 6: GitHub Issue 起票 と 作業ブランチ作成

### 6-1. Issue を立てる

`references/body-templates.md` の「Issue 本文」を埋め、`$env:TEMP\claude\add-feature\issue-body.md` に書き出してから:

```
${CLAUDE_SKILL_DIR}/scripts/create-issue.ps1 -Title "<簡潔な日本語タイトル>" -BodyFile "$env:TEMP\claude\add-feature\issue-body.md" -Label "<enhancement | bug | documentation>"
```

- 存在しないラベルはスクリプトが自動で外す（新規作成しない）。`notes` にその旨が入る。
- 返った JSON の `number` を控える（以降 `#<issue-number>` として使う）。

### 6-2. 作業ブランチを作成する

**`main` 上で直接実装しない。** スクリプトが最新化・既存ブランチ衝突・未コミット変更を検査する。

```
${CLAUDE_SKILL_DIR}/scripts/new-branch.ps1 -Prefix <feat|fix|docs> -Title <開発タイトル>
```

- prefix は `development-guidelines.md` の Git 規約に従う。規約が無ければ既存履歴（`git log --oneline --decorate -20`）に倣い、機能追加は `feat`、修正は `fix`、ドキュメントは `docs`。
- Step 0 で `defaultBranch` が `main` 以外だった場合は `-BaseBranch <name>` を渡す。
- ステアリングファイルはこのブランチに含める（先に作成済みのものをそのままブランチへ持ち込む）。

## Step 7: 永続的ドキュメント更新（必要な場合のみ）

Step 2 で影響ありと判定していれば、該当する `docs/` 内のドキュメントを更新する。設計に影響しないなら何もしない。

更新は `doc-writer` サブエージェントに 1ファイルずつ委譲する（既存ファイルは上書きせず `Edit` で更新される）。渡すもの: 対象ファイルのパス、今回の変更内容、`design.md` に書いた `docs/` 更新方針。

## Step 8: 実装

`tasklist.md` に従って実装する。`development-guidelines.md` の規約（命名・スタイル・テスト・Git）と `repository-structure.md` の配置ルールを順守する。
**`tasklist.md` は細かな作業ごとに編集しない。** 進捗はセッション内のタスク管理（TodoWrite 等）で追い、`tasklist.md` の更新は計画変更時と完了時（Step 11 冒頭）にまとめて行う。

## Step 9: 品質チェック（lint・型・テスト）

```
${CLAUDE_SKILL_DIR}/scripts/quality-check.ps1
```

`package.json` / `pyproject.toml` を自動判別し、設定があるものだけを実行する（勝手に新ツールを導入しない）。
返る JSON の `allGreen` / `checks[]`（name / status / exitCode）で判断する。

- 新規/変更ロジックに対するテストを追加・更新する（Step 1 のダイジェストで得たテスト規約に従う）。
  - **プロジェクトに `test-writer` エージェントが定義されていれば、テストの作成・実行を委譲する。** 実装した内容とテスト規約を渡し、返させるのは「追加/更新したテストファイル」「実行結果」「失敗があればその要点」だけ（テスト本文や全ログは返させない）。無ければ従来どおりメインで行う。
- `FAIL` があれば修正し、`allGreen` が true になるまで繰り返す。
- `SKIP` されたものは最終報告に明記する。

## Step 10: 動作検証（`general-purpose` に委譲）

テストだけでなく、実際にアプリを動かして期待挙動を確認する。**サーバログ・ブラウザのスナップショットは極めて冗長なので、組み込みの `general-purpose` サブエージェントに実行させ、結論だけを受け取る。**

依頼内容: 「アプリを起動し、次の期待挙動を確認すること」＋確認してほしい挙動を具体的に列挙する。プロジェクト種別に応じて:

- CLI/ライブラリ: エントリポイントやサンプル実行で挙動確認
- API(FastAPI/Next.js Route Handler 等): サーバ起動 → 対象エンドポイントを叩いて応答確認
- フロント/ブラウザ: 起動して該当画面の動作を確認

起動方法が自明でなければ、サブエージェントに `/run` スキルの手順に従わせる。

返させるのは次の3点だけ:

1. 実行したコマンド
2. 観測した挙動（レスポンス本文や画面の要点のみ。全文ログは返させない）
3. 期待どおりか（❌ の場合は原因の手がかり）

期待どおりでなければメインで修正し、再度検証を依頼する。**起動したサーバやプロセスを終了させることまで依頼に含める**（バックグラウンドプロセスの取り残しを防ぐ）。

## Step 10.5: PR 前のコードレビュー

**プロジェクトに `code-reviewer` エージェントが定義されていれば**、commit の前に差分レビューを委譲する。実装したのは自分なので、レビューは別コンテキストの目で行うほうが効く。

- 依頼内容: 「現在の作業ブランチの `git diff`（main との差分）を、バグ・セキュリティ・パフォーマンス・設計妥当性の観点でレビューし、重大度付きの指摘リストだけを返すこと」
- **Critical / Major は PR を作る前に潰す。** 修正後、影響が大きければ Step 9 の品質チェックをやり直す。
- Minor は判断して、直さない場合は最終報告に残す。
- `code-reviewer` が無いプロジェクトではこの Step をスキップする（その旨を最終報告に明記する）。

## Step 11: commit & push

`tasklist.md` を最終状態（全チェック完了 or 残課題明記）に更新してから、まとめてコミットする。

`references/body-templates.md` の「コミットメッセージ」を埋め、`$env:TEMP\claude\add-feature\commit-msg.txt` に書き出してから:

```
${CLAUDE_SKILL_DIR}/scripts/commit-and-push.ps1 -MessageFile "$env:TEMP\claude\add-feature\commit-msg.txt"
```

- スクリプトが `main` / `master` への直接コミットを拒否し、機密ファイルらしき名前（`.env` / `*.pem` / `*.key` / `id_rsa` / `credentials.json` 等）がステージされていたらステージを解除して中断する。**これは名前ベースの検査であり内容は見ていない。** 返った JSON の `staged[]` を必ず目視で確認する。
- ステージ対象を絞りたい場合は `-Paths <p1>,<p2>` を渡す（既定は `git add -A`）。
- コミットメッセージ形式は `development-guidelines.md` の Git 規約に従う（規約が無ければ既存履歴に倣い Conventional Commits）。

## Step 12: PR 作成 → main へマージ

`references/body-templates.md` の「PR 本文」を埋め、`$env:TEMP\claude\add-feature\pr-body.md` に書き出してから:

```
${CLAUDE_SKILL_DIR}/scripts/open-pr.ps1 -Title "<type>: <変更内容の簡潔な要約>" -BodyFile "$env:TEMP\claude\add-feature\pr-body.md"
```

PR 作成後、**Step 9 の lint・型・テストがすべて green で、Step 10 の動作検証も期待どおりだった場合に限り** マージする。

```
${CLAUDE_SKILL_DIR}/scripts/merge-pr.ps1 -QualityGreen -ReviewClean
```

`merge-pr.ps1` が「マージを止める条件」の門番になっている:

- **スクリプトが自分で検証する** — コンフリクト（`mergeable`）、ブランチ保護・レビュー必須によるブロック（`mergeStateStatus`）、CI の失敗 / pending（`gh pr checks`）
- **呼び出し側が主張する** — `-QualityGreen`（lint / 型 / テストが green）、`-ReviewClean`（Critical / Major が解消済み）。**スイッチを付け忘れるとマージを拒否する。** 条件を満たしていないのにスイッチを付けてはならない
- マージ方式はリポジトリ設定から自動選択される（`-MergeMethod merge|squash|rebase` で上書き可）
- マージ後、`main` の最新化と、`Closes #N` で紐づく Issue のクローズ確認まで行う

いずれかのガードで拒否された場合（`merged: false`）は、**PR は作成したままマージせず**、`reason` をユーザーに提示して判断を仰ぐ。

## Step 13: 完了報告

次を簡潔に報告する:

- 作成したステアリングディレクトリ
- 起票した Issue（番号・URL）と作成した PR（番号・URL）、マージ結果
- 変更/追加したファイル一覧
- 更新した `docs/`（あれば）
- lint・型・テストの結果（`SKIP` されたものを明記）、動作検証で確認した挙動
- Step 10.5 のレビュー結果（実行したか / 指摘件数 / 直さずに残した Minor）
- 残課題・次のステップ

**同じ説明を Issue・PR・完了報告へ再掲しない。** リンクと差分要約を中心にする。
`docs/` を更新した場合は、`/review-docs` でドキュメント整合性を確認することを提案する。

---

## 停止条件

次の場合は安全に進められる範囲まで実行し、PR または作業ブランチを残して停止し、状況と必要な対応を報告する:

- 承認済みの要求を変える必要が生じた
- ユーザーの未コミット変更と安全に分離できない
- 必須の lint・型・テスト・動作検証が失敗または実行不能のまま解消できない
- `merge-pr.ps1` のガードで拒否された（コンフリクト・CI 失敗/pending・ブランチ保護・レビュー必須）
- Step 5 で承認されていない外部操作・破壊的操作が必要になった

## 守ること

- **CLAUDE.md のステアリング規則を最優先**で順守する（命名・ファイル構成が本手順と異なればそちらに従う）。
- **`docs/` の全文をメインコンテキストに読み込まない。** 前提は `docs-digest` のダイジェストで足りる。細部が要るときだけ出典を頼りに該当箇所を `Read` する（`/dev-docs`「サブエージェント運用方針」）。
- **サブエージェントに承認を代行させない。** Step 5 の承認ゲートは必ずメインで取る。
- **git / gh の操作は同梱スクリプト経由で行う。** インラインでシェルを組み立てない（ヒアドキュメントは PowerShell で動かない）。
- ステアリングは `.steering/[YYYYMMDD]-[開発タイトル]/` に作る。既存ディレクトリは上書きせず、新規作業は新規ディレクトリ。
- 承認ゲート（Step 5）より前に、コードを書かない・Issue を立てない・ブランチを切らない。
- **`main` に直接コミットしない。** 必ず作業ブランチを切り、PR 経由で main に入れる。
- commit / push / PR 作成 / マージは、Step 5 の承認を得た本フロー内でのみ行う。品質チェックが green でない状態でマージしない。
- `git push --force` / `git reset --hard` / ブランチ削除など、作業を失う操作は行わない（マージ後の `--delete-branch` を除く）。
- 機密情報（APIキー等）をコード・ドキュメント・Issue・PR 本文に書かない。一時ファイルはリポジトリ内に置かない。
- 永続的ドキュメントと作業単位ドキュメントを混同しない。`docs/` の更新は設計に影響する場合のみ。
