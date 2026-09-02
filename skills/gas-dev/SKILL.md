---
name: gas-dev
description: GAS（Google Apps Script）開発を一気通貫で回すオーケストレータースキル。①gas-clone（スクリプトIDの特定とローカルへのクローン）→ ②business-understanding（業務整理）→ ③dev-docs init（要件定義・永続ドキュメント整備）→ ④add-feature（機能開発）→ ⑤gas-push（clasp status 確認とリモート反映）の5フェーズを、プロジェクトの状態を検出して途中からでも正しい順に進める。「GAS開発を始めたい」「この案件のGAS改修を最初から最後まで」「GAS開発フローで進めて」「クローンからpushまで一通り」「いつものGASの流れで」など、GAS開発の工程全体・複数フェーズにまたがる依頼が来たら必ずこのスキルを使うこと。単発の作業には各スキルを直接使う（クローンだけ→gas-clone、pushだけ→gas-push、機能追加だけ→add-feature、業務整理だけ→business-understanding）。
argument-hint: [開発したい内容の説明 | スクリプトID/URL]
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/state.ps1 *)
  - PowerShell(${CLAUDE_SKILL_DIR}/scripts/state.ps1 *)
---

# GAS 開発の一気通貫フロー（gas-dev）

GAS 開発を「クローン → 業務整理 → 要件定義 → 機能開発 → リモート反映」の 5 フェーズで回すオーケストレーター。
各フェーズの実体は既存スキルであり、本スキルは**状態を検出して正しい順に呼び出し、フェーズ間を橋渡しする**ことに徹する。手順の真実は各スキル側にあり、ここで重複させない。

| Phase | 内容 | 呼び出すスキル | 完了の目印 |
| --- | --- | --- | --- |
| 1 | ローカルにクローン（スクリプトIDは Claude が特定） | `gas-clone` | `.clasp.json` がある |
| 2 | 業務整理（As-Is・課題・改善機会） | `business-understanding` | `docs/business-understanding.md` がある |
| 3 | 要件定義・永続ドキュメント整備 | `dev-docs`（引数 `init`） | `CLAUDE.md` + `docs/` 一式がある |
| 4 | 機能開発 | `add-feature` | ステアリング完了＋実装済み |
| 5 | リモートへ反映 | `gas-push` | push 完了 |

引数: `$ARGUMENTS`

- 開発したい内容の説明があれば控えておき、Phase 4 で `add-feature` にそのまま渡す。
- スクリプトID / URL があれば Phase 1 で `gas-clone` に渡す。

## 進め方

1. `${CLAUDE_SKILL_DIR}/scripts/state.ps1` を実行し、返った JSON の `suggestedPhase` から開始フェーズを決める。完了済みフェーズは飛ばす。
   - `suggestedPhase` は推奨であって強制ではない。ユーザーがフェーズの省略・指定を明示したらそれに従う（例: 「業務整理は済んでいる」→ Phase 3 から）。迷ったら現在地の認識（「Phase 2 から始めます。業務整理がまだのため」など1行）を添えて進める。
2. 各フェーズは **Skill ツールで該当スキルを呼び出して**実行する。フェーズ内の手順・承認ゲート・成果物の書式は各スキルの定義に従う。
3. フェーズが 1 つ終わるごとに、完了物と次フェーズを 2〜3 行で報告してから次へ進む。
4. スキル内の承認ゲート（add-feature の Step 5、gas-push の確認など）では必ず停止し、承認を代行しない。

## GAS プロジェクト特有の注意（フェーズ間の橋渡し）

- **git**: clasp clone しただけのディレクトリは git リポジトリではない。`add-feature` は git/GitHub が無ければ Issue/PR 工程を自動でスキップするが、履歴を残すため Phase 2 に入る前に `git init` ＋初回コミットを提案する（強制はしない。`.gitignore` に `.clasp.json` を入れるかは共有方針次第なのでユーザーに一言確認する）。
- **push 対象**: GAS へ push されるのは `.js` / `.gs` / `.html` / `appsscript.json` のみ。Phase 2〜4 で作る `docs/` / `.steering/` / `CLAUDE.md` は push されない（`clasp status` の `untrackedFiles` に出るのが正常）。リモートを汚す心配はない。
- **要件の受け渡し**: Phase 2 の `docs/business-understanding.md`（課題一覧・改善機会リスト）は Phase 3 の要件定義の主要な入力。スコープ・優先順位の判断で迷いが出たら `decision-rules` スキルを間に挟む。
- **動作検証**: GAS はローカル実行できない。push 前はテスト関数・静的確認・コードレビューが中心になり、実挙動の最終確認は Phase 5 の push 後に Apps Script エディタ（`clasp open-script`）やスプレッドシート上で行う。`add-feature` の動作検証 Step はこの前提で読み替える。
- **Phase 4 → 5**: add-feature の完了報告に「次は gas-push でリモートへ反映する」ことを含め、そのまま Phase 5 へ進む。push の点検・確認ルールは gas-push 側の定義に従う。

## 守ること

- 全フェーズを 1 ターンで無理に完走しようとしない。各スキルのヒアリング・承認ゲートを尊重する。
- フェーズの中身を本スキルで再実装しない。各スキルの手順が更新されたら自動でそちらに従うのが、この分割の目的である。
- Phase 5 の push 確認（リモート上書きの注意）を省略しない。
