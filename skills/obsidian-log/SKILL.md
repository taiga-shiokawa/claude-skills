---
name: obsidian-log
description: Claude Code との会話を構造化サマリのノート1枚にまとめ、Obsidian 保管庫「AI Log」（%USERPROFILE%\Documents\AI Log）に保存し、続けて保管庫の Private リポジトリ（taiga-shiokawa/obsidian-ai-log）へコミット・push するスキル。「今の会話をメモして」「Obsidian に記録して」「ログを残して」「保管庫に残して」「今日の作業を保管庫にまとめて」「このセッションをノートにして」「保管庫を同期して」と言われたとき、またはセッションの区切りで /obsidian-log と入力されたときに必ず使う。Obsidian・保管庫・ノート・ログという語が出たら、明示的に「スキルを使って」と言われなくてもこのスキルを使うこと。要約を画面に表示するだけで保存が不要な依頼には使わない。Word の開発日誌や Excel 管理台帳への記録は別スキル（daily-report）なのでこちらは使わない。保管庫以外のリポジトリに対する git 操作にも使わない。
---

# obsidian-log — 会話を Obsidian 保管庫に残す

このセッションの会話を **構造化サマリのノート1枚** にまとめ、Obsidian 保管庫に直接書き込む。

会話ログをそのまま貼るのではなく、**後から検索して役に立つ形**に再構成することが目的。
全文は `~/.claude/projects/` の JSONL に残っているので、ここでは「読み返す価値のある要点」だけを残す。

保管庫は Private な GitHub リポジトリ（`taiga-shiokawa/obsidian-ai-log`）で管理している。
**ノートを書いて push するところまでが1セット。**

## 保管庫の場所

```powershell
$VAULT = Join-Path $env:USERPROFILE 'Documents\AI Log'
```

現 PC では `C:\Users\GOOYAラウンダー6\Documents\AI Log`。これは**例示であって、この絶対パスを
スキルの中に書き込まない**。ユーザー名に非 ASCII 文字が入っていて、PC を入れ替えると変わる。
必ず `$env:USERPROFILE` から組む。

ただし **Write ツールは環境変数を展開しない**ので、書き込みには実体の絶対パスが必要。
手順1 の存在確認コマンドが解決済みのパスを `VAULT:` 行に出すので、その出力をそのまま使う。

このフォルダ自体が Obsidian 保管庫（直下に `.obsidian` がある）で、**同時に Git リポジトリ**でもある。
保管庫はファイルシステム上の普通のディレクトリなので、`.md` を置けば Obsidian に反映される。
プラグインや API は不要で、Obsidian が起動していなくてもよい。

**ノートは保管庫直下に置く。** プロジェクト別・ツール別のサブフォルダは作らない。
区別は frontmatter の `project` とタグで取る。この保管庫は Codex など他の AI コーディング
ツールのログとも共有する前提なので、どのツールで書いたログかを示す `claude-code` タグは必ず入れる。

保管庫直下の `codex-skills/` は **別リポジトリ（`taiga-shiokawa/codex-skills`）のクローン**で、
`.gitignore` で除外してある。ノートではないので、ファイル一覧にも `## 関連` のリンク先にも出さない。

---

## 手順0 — 素材を確定する

原則として **いまコンテキストにある会話** からまとめる。会話が手元にあるならこの手順は飛ばしてよい。

以下の場合だけ、セッションの JSONL を読んで補う:

- コンテキストが圧縮されていて、序盤のやり取りが手元にない
- ユーザーが過去のセッションを指定した

同梱スクリプトが JSONL の場所を解決し、`user` / `assistant` の本文だけを抜き出す
（tool_result は巨大なので読まない）。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\obsidian-log\scripts\read-session.ps1" -Tail 80
```

- `-InfoOnly` … セッション ID とファイルパスだけ表示（frontmatter の `session` を埋めるとき用）
- `-Tail <n>` … 末尾 n 発言だけ（省略すると全部出て重い。まず 60〜100 から）
- `-Cwd "<dir>"` … 別プロジェクトのセッションを対象にする
- `-Path "<file.jsonl>"` … ファイルを直接指定する

スクリプトが解決するのは**そのディレクトリで最後に更新された JSONL** = 通常はいま動いている
セッション。過去セッションを名指しされたら `-InfoOnly` の出力にある親フォルダを一覧して選ぶ。

> 同梱スクリプトはいずれも **UTF-8 BOM 付き**で保存してある。Windows PowerShell 5.1 は BOM の無い
> ファイルを ANSI として読むため、BOM を落として保存し直すと日本語コメントが壊れて
> パースエラーになる。編集したときは BOM 付きで書き戻すこと。

## 手順1 — 保存先を決める

```
<VAULT>\<YYYY-MM-DD>　<タイトル>.md
```

- `<タイトル>` はそのセッションの主題を 10〜20 字程度の日本語で。
  スキルに引数が渡されたらそれを優先する
- 日付とタイトルの間は **全角スペース**（例: `2026-08-31　obsidian-logスキル作成.md`）
- Windows のファイル名に使えない `\ / : * ? " < > |` はタイトルから外す。
  全角の `：` `／` などへ置換してもよいが、検索しづらくなるので原則は使わない書き方にする
- 同名ファイルが既にあるときは末尾に半角スペース + 連番（` 2`）を付ける。
  **既存ノートは絶対に上書きしない。** 書く前に必ず存在確認する:

```powershell
$V = Join-Path $env:USERPROFILE 'Documents\AI Log'
"VAULT: $V"
Get-ChildItem -LiteralPath $V -Filter "2026-08-31*" | Select-Object -ExpandProperty Name
```

出力の `VAULT:` 行が保管庫の絶対パス。**Write ツールにはこれを使う**（環境変数は展開されない）。

## 手順2 — ノートを書く

```markdown
---
date: 2026-08-31
project: my-project
session: e91558d5
tags:
  - claude-code
  - <内容に応じたタグ>
---

# <タイトル>

## 何をやったか

## 決めたこと・その理由

## 詰まった点と解決

## 変更したファイル

## 次にやること

## 関連
[[関連ノート]]
```

- `project` は cwd の basename（`Split-Path -Leaf (Get-Location)`）
- `session` は session-id の先頭8文字。手順0 のスクリプトの `SESSION_SHORT` がそれ。
  元の JSONL を辿り直すための手がかりなので、面倒でも入れておく価値がある
- `tags` の `claude-code` は **発生源の識別子**。保管庫を他ツールと共有するため必ず残す
- 各セクションは箇条書き中心。**中身が空になるセクションは見出しごと削除する**。
  空見出しが並ぶと、後から見たときに「書いてないのか、無かったのか」が判別できなくなる
- 「決めたこと」は結論だけでなく **なぜそう決めたか** を必ず1行添える。
  後から読み返したときに価値があるのはそこ
- `## 関連` では保管庫の既存ノート名に一致する語があれば `[[...]]` で結ぶ。
  リンク先が未作成でも構わない（未解決リンクとして残る）。既存ノート名はこれで見る:

```powershell
Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE 'Documents\AI Log') -Filter *.md |
  Select-Object -ExpandProperty Name
```

**`-Recurse` を付けない。** 付けると `codex-skills/` の中の `SKILL.md` や `README.md` まで拾い、
件数が4倍近くに膨らんで、ノートでないものへ `[[SKILL]]` のようなリンクを張ってしまう。

Obsidian 側で `properties` / `tag-pane` / `backlink` / `global-search` が有効なら、
frontmatter・タグ・ウィキリンクはそのまま検索・回遊の導線として働く。

## 手順3 — 秘密情報を落とす（必須）

**要約であっても、以下は書かない:**

- `.env` の値、API キー、トークン、パスワード、接続文字列、個人を特定する第三者の情報

触れる必要があるときは値を出さず **キー名だけ** にする（例: `OPENAI_API_KEY を設定した`）。

保管庫は Private リポジトリとして GitHub に push される。**一度コミットすると履歴から消すのが
面倒**なので、端末外に出る前提でここで落とす。手順5 のスクリプトも機械的なスキャンをかけるが、
あれは取りこぼしを拾う保険で、判断はここでやる。

## 手順4 — 書き込む

- **Write ツールで直接書き込む。** PowerShell の `Set-Content` / `Out-File` は既定の文字コードが
  UTF-8 とは限らず、日本語ノートが文字化けする。書き込みは Write ツールに任せる
- 保管庫フォルダが無い場合だけ `New-Item -ItemType Directory -Force` で作ってからリトライ
- ノートが書けた時点でこのスキルの主目的は達成している。**手順5 の同期が失敗しても、
  ノートを消したり書き直したりしない**

## 手順5 — GitHub へ同期する

ノートを書き終えたら同梱スクリプトを **1回だけ** 呼ぶ。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\obsidian-log\scripts\sync-vault.ps1" -NoteDate 2026-08-31 -Title "obsidian-logスキル作成"
```

`-NoteDate` と `-Title` はコミットメッセージ（`log: <YYYY-MM-DD> <タイトル>`）用。手順1 で決めた
ものをそのまま渡す。省略すると件数だけのメッセージになる。

スクリプトは**保管庫の未コミット変更を全部**まとめて1コミットにする。今回書いたノートだけを
選ばない。この保管庫は Codex とも共有していて、Codex が書いたノート（タグ `codex`）は
誰もコミットしないまま溜まる。ここが唯一の同期機会なので通りかかったときに全部拾う。

出力の先頭トークンだけ見ればよい。

| 出力 | 終了コード | 意味 | やること |
| --- | --- | --- | --- |
| `SYNCED:` | 0 | コミットして push 済み | 手順6 で報告 |
| `NOTHING_TO_COMMIT:` | 0 | 未コミットの変更なし | 手順6 で報告 |
| `SECRET_DETECTED=` | 2 | 秘密情報を検出。**何もコミットしていない** | 該当行から値を消して呼び直す |
| `NOT_A_REPO:` / `NOT_A_VAULT:` | 3 | まだセットアップされていない | 付録「初回セットアップ」を案内する |
| `IN_PROGRESS:` / `REBASE_CONFLICT:` | 4 | 手作業が必要な git の状態 | 何もせず報告する |
| `OFFLINE:` / `PUSH_FAILED:` / `PUSH_SKIPPED:` | 5 | ローカルコミットのみ | 報告だけ。**リトライしない** |

- **push の失敗はセッションを止める理由にならない。** コミットは済んでいるので次回の同期で
  一緒に上がる。終了コードが 0 でなくても失敗として報告せず、報告に1行足すだけにする
- `-SkipSecretScan` で押し通さない。検出されたら**ノートを直す**のが正しい対処
- `git push --force` や `git reset --hard` をスキルから実行しない。`REBASE_CONFLICT` は
  スクリプトが `rebase --abort` して元に戻してあるので、解決コマンドを提示するだけにする
- ユーザーが「同期しないで」「ローカルだけ」と言ったらこの手順を飛ばし、飛ばしたことを報告する
- スクリプトを複数回呼ばない。2回目は `NOTHING_TO_COMMIT` になるだけで情報が増えない

## 手順6 — 報告する

保存と同期を**まとめて 2〜3 行**で報告する。手順4 と手順5 で別々に喋らない。

```
保存: C:\Users\GOOYAラウンダー6\Documents\AI Log\2026-08-31　obsidian-logスキル作成.md
セクション: 何をやったか / 決めたこと / 詰まった点 / 変更したファイル / 次にやること
同期: 2件をコミットして push（SYNCED a1b2c3d）
```

- 上書きを避けて連番を付けた場合は、そのことも伝える
- `OFFLINE` / `PUSH_FAILED` のときは「ローカルにコミット済み。次回の同期で上がる」と添える。
  ユーザーに対処を求めない
- 同期でついでに拾った他ツールのノートがあれば件数だけ触れる（ファイル名は並べない）

---

## 付録 — 初回セットアップ（1回だけ）

`NOT_A_REPO:` が出たらここ。同梱スクリプトが冪等に処理する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\obsidian-log\scripts\ensure-vault-repo.ps1" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\obsidian-log\scripts\ensure-vault-repo.ps1"
```

やること: `git init -b main`（`init.defaultBranch` が未設定だと `master` になり GitHub の既定
`main` とずれるので `-b` は必須）→ `core.quotepath=false` と `i18n.*` の設定 →
`.gitignore` / `.gitattributes` / `README.md` を無い場合だけ作成 → 初回コミット →
`gh repo create taiga-shiokawa/obsidian-ai-log --private` して push。

- **GitHub にリポジトリを作る外向きの操作を含む。** 勝手に実行せず、必ずユーザーに確認する
- `gh` のログインアカウントがリポジトリの owner（`taiga-shiokawa`）と一致しない場合は中断する。
  会社アカウントではなく個人アカウントで運用するため
- `codex-skills/` が既に追跡されていたら中断する。壊れた gitlink は後から直しにくい

## 付録 — 新しい PC で復元する

`git init` ではなく **clone**。保管庫そのものがリポジトリなので、クローン先をそのまま
Obsidian で開けばよい。コピー手順もジャンクションも要らない。

```powershell
gh auth login
gh repo clone taiga-shiokawa/obsidian-ai-log "$env:USERPROFILE\Documents\AI Log"
```

- Obsidian → 「別の保管庫を開く」→「フォルダを保管庫として開く」でこのフォルダを指定する。
  `.obsidian/` の設定を追跡しているので、有効プラグインとグラフ設定はそのまま復元される
- 認証は Windows 資格情報マネージャーに入るので、PC ごとに `gh auth login` をやり直す
- `codex-skills/` は含まれない。必要なら保管庫内で別途 clone する（`.gitignore` 済み）
- **旧 PC がまだ生きているうちは、両方から push すると履歴が分かれる。** 移行期間は
  使う側で先に `git pull --rebase` する（`sync-vault.ps1` は自動でこれをやる）
- このスキル自身（`~/.claude/skills/obsidian-log/`）は保管庫ではなく
  `taiga-shiokawa/claude-skills` の側にある。そちらからコピーして戻す
