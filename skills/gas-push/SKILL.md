---
name: gas-push
description: ローカルの GAS（Google Apps Script）プロジェクトの変更を clasp status で点検し、問題なければ clasp push でリモート（script.google.com 上のスクリプト）へ反映するスキル。push はリモートの内容を丸ごと上書きするため、push 対象一覧の提示と確認を必ず挟む。「pushして」「GASに反映して」「リモートに上げて」「スクリプトを更新して」「clasp pushして」「本番のGASに反映」など、ローカル→リモートの反映に関することを言ったら必ずこのスキルを使うこと。リモート→ローカルの取得には使わない（それは gas-clone / clasp pull）。版の公開（clasp deploy）は範囲外だが、必要な場合の案内は行う。
argument-hint: []
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/*.ps1 *)
  - PowerShell(${CLAUDE_SKILL_DIR}/scripts/*.ps1 *)
---

# GAS への反映（gas-push）

ローカルの変更を `clasp status` で点検し、問題なければ `clasp push` でリモート（script.google.com 上のプロジェクト）へ反映する。

**`clasp push` はリモートの内容をローカルで丸ごと上書きする。** Web エディタ側でだけ加えられた変更は失われる。だからこの点検と確認を挟む。

```
preflight（status込み） → push対象の点検 → 【確認】 → push（必要なら -Force 再実行） → 報告
```

## 同梱スクリプト

clasp の操作は同梱スクリプト経由で行い、生出力をメインコンテキストに載せない。

| スクリプト | 用途 |
| --- | --- |
| `${CLAUDE_SKILL_DIR}/scripts/preflight.ps1` | clasp導入・ログイン・.clasp.json・push対象一覧を1つのJSONで取得 |
| `${CLAUDE_SKILL_DIR}/scripts/push.ps1 -Confirmed [-Force]` | ガード付きで clasp push を実行 |

## Step 0: preflight

`preflight.ps1` を実行し、返った JSON で分岐する:

- `claspInstalled: false` → `npm install -g @google/clasp` をユーザーに提案する。
- `loggedIn: false` → **`clasp login` はユーザー自身に実行してもらう**（ブラウザでの Google 認証を Claude が代行することは禁止事項）。
- `hasClaspJson: false` → clasp プロジェクトではない。クローンから始めるなら `/gas-clone` を案内して終了する。
- `warnings` は Step 1 の点検で扱う。

## Step 1: push 対象の点検

`filesToPush` / `untrackedFiles` を見て、次を確認する:

1. `filesToPush` が空でない（空なら push する意味がない — その旨を報告して終了する）。
2. **今回の作業で変更したファイルが `filesToPush` に含まれている。** 含まれていなければ拡張子や `.claspignore` の問題を疑う。GAS に push されるのは `.js` / `.gs` / `.html` / `appsscript.json` のみで、`docs/` や `.md`、`.claude/` が `untrackedFiles` に出るのは正常。
3. 想定外のファイルが混ざっていない（実験用の一時ファイルなど。あれば `.claspignore` への追加を提案する）。
4. `appsscript.json` を今回変更したかを把握しておく（変更していた場合、push 時にマニフェスト上書きの追加確認が要ることがある — Step 3）。

git リポジトリなら `git status` / `git diff --stat` の要約を添えると、ユーザーが「何をどれだけ変えたか」を判断しやすい。

## Step 2: 確認

push 対象（件数＋主なファイル）と「リモート側にしかない変更は失われる」旨を**簡潔に**提示する。

- ユーザーがこの依頼の中で push まで明示的に指示しており（例: 「問題なければ push して」、`/gas-dev` の一連フロー）、かつ Step 1 の点検がすべて問題なしなら、提示のうえそのまま Step 3 へ進んでよい。
- それ以外（依頼が曖昧 / 点検で警告あり / このプロジェクトで初めての push / 複数人が Web エディタで編集する運用）は、**承認を得るまで push しない**。

## Step 3: push 実行

```
${CLAUDE_SKILL_DIR}/scripts/push.ps1 -Confirmed
```

返った JSON で分岐する:

- `pushed: true` → Step 4 へ。
- `needsForce: true` → マニフェスト（`appsscript.json`）がリモートと食い違っている可能性が高い。ローカルの `appsscript.json` の変更内容（タイムゾーン・スコープ・ライブラリ・依存サービス等）を確認して説明し、**ユーザーの承認を得てから** `-Confirmed -Force` で再実行する。
- その他の失敗 → `output` / `notes` を基に原因（アクセス権限・ネットワーク・コードの構文エラー等）を調べて対処する。構文エラーなら修正して Step 1 からやり直す。

## Step 4: 報告

- push したファイル数・主なファイルを簡潔に報告する。
- 動作確認の導線を案内する: `clasp open-script`（Apps Script エディタを開く）。トリガー起点の処理なら実行ログの確認も（`clasp logs`）。
- **push は「保存」であって「デプロイ（版の公開）」ではない。** Web アプリ / API 実行可能ファイルとして公開しているプロジェクトでは、公開版の更新に `clasp deploy`（または既存デプロイの更新）が別途必要なことを伝える（本スキルの範囲外）。エディタ上での実行・テスト用デプロイは push だけで最新化される。

## 守ること

- push は必ず `push.ps1 -Confirmed` 経由で行う。Step 2 の確認を経ずに `-Confirmed` を付けない。マニフェスト差分をユーザーに説明して承認を得るまで `-Force` を付けない。
- `clasp push --watch` は使わない（対話プロセスが残り続ける）。
- リモート側の変更が疑われる場合は push せず、ユーザーに状況を伝えて判断を仰ぐ。
