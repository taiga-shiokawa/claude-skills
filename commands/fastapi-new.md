---
description: FDE学習プロジェクト用のFastAPIプロジェクト（uv 構成）を新規作成する
argument-hint: <project-name> [--with-openai] [--pattern 2|3|4]
---

# FastAPI新規プロジェクト作成（uv）

FDE（Forward Deployed Engineer）学習プロジェクトの規約に沿って、FastAPIプロジェクトを
`uv` + `pyproject.toml` でスキャフォールドする。

実行直後に「プロジェクトの規模感」を選択式で質問し、その答えに応じてディレクトリ構成
（パターン2 / 3 / 4）を使い分ける。**基本（既定・推奨）はパターン3。**

引数: `$ARGUMENTS`

## 作業手順

### Step 1: 引数の確認

`$ARGUMENTS` を解析する：
- 第1引数 = プロジェクト名（必須。例: `fastapi-email-assist`）
- `--with-openai` フラグがあれば OpenAI SDK もインストールする
- `--pattern 2|3|4` フラグがあれば Step 2 の質問をスキップし、その番号のパターンを採用する

プロジェクト名が指定されていない場合は、ユーザーに聞く。
すでに目的のディレクトリ内にいる場合（空のフォルダが用意済みなど）は、新しくサブフォルダを作らず、
カレントディレクトリをプロジェクトルートとして扱う。

### Step 2: 規模感を質問してパターンを決定

`--pattern` フラグが**無い場合**、`AskUserQuestion`（multiSelect: false）で次を質問する。
header は「規模感」、推奨（パターン3）を先頭に置き label に「(推奨)」を付ける。

- **中規模 — パターン3 技術レイヤー (推奨)**
  責務（設定 / API / スキーマ / モデル / DB操作）ごとに `app/` 配下を分割する標準構成。
  1つのドメイン中心で、置き場所を自明にしたいAPI向け。**迷ったらこれ。**
- **小規模 — パターン2 種類別フラット**
  root の `main.py` ＋ `routers/` でエンドポイントだけ分割し、`schemas.py` などは1枚で持つ
  公式チュートリアル型。学習の最初・小さめのAPI向け（必要になったらP3へ育てやすい）。
- **大規模 / 拡張前提 — パターン4 ドメイン縦割り**
  機能ごとに `src/<feature>/`（router/schemas/service…）で縦割りする構成。
  機能が増え続ける・チーム開発・1機能=1フォルダで完結させたい場合向け。

選ばれたパターン番号を以降のステップで使う。**以降、`<P>` は採用パターン番号を指す。**

### Step 3: uv の確認（無ければインストール）

```bash
command -v uv >/dev/null 2>&1 && uv --version || echo "uv missing"
```

`uv` が無ければインストールする（macOS）：

```bash
# Homebrew があれば
brew install uv
# 無ければ公式インストーラ
# curl -LsSf https://astral.sh/uv/install.sh | sh
```

インストール後、`uv --version` で確認する。

### Step 4: プロジェクトをスキャフォールド

`uv init` で雛形を作る（`--package` は付けない）。パターン3/4 でも `--package` は使わず、
`app/` や `src/` は **Step 5 で手動作成**する（ビルド対象パッケージにはせず、`uvicorn` の
モジュールパス指定で起動するため）。

- 新規にサブフォルダを作る場合:
  ```bash
  uv init <project-name>
  cd <project-name>
  ```
- カレントディレクトリをルートにする場合:
  ```bash
  uv init --name <project-name> .
  ```

これで `pyproject.toml` / `main.py` / `.gitignore` / `.python-version` / `README.md` が生成される
（uvのバージョンで多少前後する）。パターン3/4 では、生成された root の `main.py` は Step 5 で
削除し、`app/` または `src/` 配下に置き直す。

### Step 5: フォルダとファイルを整える（パターン別）

採用パターン `<P>` に応じて、以下の構成になるよう調整する。

共通で作る/直すファイル（**全パターン共通**）：

**.env.example の内容：**
```
# このファイルをコピーして .env を作成し、実際の値を設定すること
# cp .env.example .env

# APP_NAME=<project-name>

# --with-openai フラグがある場合のみ追加
# OPENAI_API_KEY=sk-...
```

**.gitignore の確認・追記：** uvが生成済み（`.venv` 等）。以下が無ければ追記する。
```
.env
__pycache__/
*.pyc
.DS_Store
```

---

#### パターン2（種類別フラット / routers）

```
<project-name>/
├── main.py            # app生成・ルーター登録
├── routers/
│   ├── __init__.py
│   └── health.py      # / と /ping
├── schemas.py         # Pydanticスキーマ（最初は空でも可）
├── .env.example
├── .gitignore
├── pyproject.toml
├── .python-version
└── README.md
```

uv init が生成した root の `main.py` は下記で上書きする。`routers/` を作成し `__init__.py` を置く。
DBモデルやDB操作が必要になったら `models.py` / `crud.py` を root に足し、エンドポイントが増えたら
`routers/` にファイルを追加していく（肥大化したらパターン3へ移行）。

**main.py：**
```python
from fastapi import FastAPI

from routers import health

app = FastAPI(title="<project-name>")

app.include_router(health.router)
```

**routers/health.py：**
```python
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/")
def root():
    """サービス稼働確認"""
    return {"status": "ok", "service": "<project-name>"}


@router.get("/ping")
def ping():
    """ヘルスチェック"""
    return {"pong": True}
```

- 起動モジュールパス: `main:app`

---

#### パターン3（技術レイヤー / app/）★既定・推奨

```
<project-name>/
├── app/
│   ├── __init__.py
│   ├── main.py            # app生成・ルーター登録
│   ├── core/
│   │   ├── __init__.py
│   │   └── config.py      # 設定（pydantic-settings）
│   ├── api/
│   │   ├── __init__.py
│   │   └── routes/
│   │       ├── __init__.py
│   │       └── health.py  # / と /ping
│   ├── schemas/
│   │   └── __init__.py    # Pydanticスキーマを置く（最初は空）
│   ├── models/
│   │   └── __init__.py    # DBモデルを置く（最初は空）
│   └── crud/
│       └── __init__.py    # DB操作を置く（最初は空）
├── tests/
│   └── __init__.py
├── .env.example
├── .gitignore
├── pyproject.toml
├── .python-version
└── README.md
```

root の `main.py` は削除する。`app/` 配下を作成し、各ディレクトリに `__init__.py` を置く。

**app/main.py：**
```python
from fastapi import FastAPI

from app.api.routes import health
from app.core.config import settings

app = FastAPI(title=settings.app_name)

app.include_router(health.router)
```

**app/core/config.py：**
```python
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "<project-name>"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
```

**app/api/routes/health.py：**
```python
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/")
def root():
    """サービス稼働確認"""
    return {"status": "ok", "service": "<project-name>"}


@router.get("/ping")
def ping():
    """ヘルスチェック"""
    return {"pong": True}
```

- 起動モジュールパス: `app.main:app`

---

#### パターン4（ドメイン縦割り / src/）

```
<project-name>/
├── src/
│   ├── __init__.py
│   ├── main.py            # app生成・各機能の router を登録
│   ├── config.py          # 全体設定（pydantic-settings）
│   └── health/            # サンプル機能モジュール（1機能=1フォルダ）
│       ├── __init__.py
│       ├── router.py      # / と /ping
│       ├── schemas.py     # この機能のPydantic（最初は空でも可）
│       └── service.py     # この機能のロジック（最初は空でも可）
├── tests/
│   └── __init__.py
├── .env.example
├── .gitignore
├── pyproject.toml
├── .python-version
└── README.md
```

root の `main.py` は削除する。`src/` 配下を作成し、各ディレクトリに `__init__.py` を置く。
新しい機能は `health/` を真似て `src/<feature>/` を増やしていく。

**src/main.py：**
```python
from fastapi import FastAPI

from src.config import settings
from src.health import router as health

app = FastAPI(title=settings.app_name)

app.include_router(health.router)
```

**src/config.py：**
```python
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "<project-name>"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
```

**src/health/router.py：**
```python
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/")
def root():
    """サービス稼働確認"""
    return {"status": "ok", "service": "<project-name>"}


@router.get("/ping")
def ping():
    """ヘルスチェック"""
    return {"pong": True}
```

- 起動モジュールパス: `src.main:app`

### Step 6: README.md を書く

採用パターンの起動モジュールパス（`main:app` / `app.main:app` / `src.main:app`）を `<module>` に入れる。

````markdown
# <project-name>

## セットアップ

```bash
uv sync
cp .env.example .env
# .env を編集して必要な値を設定
```

## 起動

```bash
uv run uvicorn <module> --reload
```

- API: http://localhost:8000
- ドキュメント: http://localhost:8000/docs

## 依存の追加

```bash
uv add <package>          # ランタイム依存
uv add --dev <package>    # 開発依存
```
````

### Step 7: 依存をインストール

```bash
uv add fastapi "uvicorn[standard]" pydantic python-dotenv
# パターン3 / 4 では設定管理に pydantic-settings を追加
uv add pydantic-settings
# --with-openai があれば追加
uv add openai
uv sync
```

`requirements.txt` は作らない。依存は `pyproject.toml` と `uv.lock` で管理する。

### Step 8: 動作確認

採用パターンの起動モジュールパスで起動して `GET /` と `GET /ping` が返ることを確認する。

```bash
# パターン2: uv run uvicorn main:app --reload
# パターン3: uv run uvicorn app.main:app --reload
# パターン4: uv run uvicorn src.main:app --reload
```

確認できたらサーバーを停止する（バックグラウンドで放置しない）。

### Step 9: 完了報告

以下を伝える：
- 採用したパターン（番号と構成名）と、そう決めた根拠（選んだ規模感）
- 作成したファイル一覧
- 起動コマンド（採用パターンの `uv run uvicorn <module> --reload`）
- 次のステップ（Pydanticでスキーマ定義など、CLAUDE.md セクション4.3の続き）

## 守ること

- 実行直後に規模感を質問し、パターンを使い分ける（既定・推奨はパターン3）。`--pattern` 指定時のみ質問を省略する
- パターンによって**起動モジュールパスが変わる**（`main:app` / `app.main:app` / `src.main:app`）。README・動作確認・完了報告すべてで一致させる
- パターン3/4 では `--package` を使わず、`app/`・`src/` は手動作成し、各ディレクトリに `__init__.py` を置く
- `.env` はコードに含めない。`.env.example` のみ作成する
- `.venv/` はgitに含めない（uv生成の .gitignore 済み）。手動の `venv/` は作らない
- APIキーは絶対にコードや pyproject.toml に書かない
- 依存は `pip install` ではなく `uv add` / `uv sync` で管理する（lockファイル `uv.lock` を生かす）
