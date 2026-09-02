---
description: FDE学習プロジェクト用の汎用Pythonプロジェクト（uv + src パッケージ構成）を新規作成する
argument-hint: <project-name> [--with <pkg,pkg,...>]
---

# Python新規プロジェクト作成（uv）

FDE（Forward Deployed Engineer）学習プロジェクトの規約に沿って、汎用的なPythonプロジェクトを
`uv` + `pyproject.toml` + src パッケージ構成でスキャフォールドする。

引数: `$ARGUMENTS`

## 作業手順

### Step 1: 引数の確認

`$ARGUMENTS` を解析する：
- 第1引数 = プロジェクト名（必須。例: `data-cleaner`）。ハイフン区切りのケバブケースを推奨
- `--with <pkg,pkg,...>` = 追加でインストールするランタイム依存（カンマ区切り。例: `--with requests,pandas`）

プロジェクト名が指定されていない場合は、ユーザーに聞く。

パッケージ名（Pythonモジュール名）はプロジェクト名のハイフンをアンダースコアに置換した名前になる
（uvが自動でそうする。例: `data-cleaner` → `data_cleaner`）。

すでに目的のディレクトリ内にいる場合（空のフォルダが用意済みなど）は、新しくサブフォルダを作らず、
カレントディレクトリをプロジェクトルートとして扱う。

### Step 2: uv の確認（無ければインストール）

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

### Step 3: プロジェクトをスキャフォールド

`uv init --package` でsrcレイアウトのパッケージ構成を生成する。

- 新規にサブフォルダを作る場合:
  ```bash
  uv init --package <project-name>
  cd <project-name>
  ```
- カレントディレクトリをルートにする場合:
  ```bash
  uv init --package --name <project-name> .
  ```

これで以下が生成される（uvのバージョンで多少前後する）：

```
<project-name>/
├── pyproject.toml
├── README.md
├── .gitignore
├── .python-version
└── src/
    └── <package_name>/
        └── __init__.py
```

### Step 4: 構成を整える

最終的に以下の構成になるよう、ファイルを追加・調整する。

```
<project-name>/
├── pyproject.toml
├── README.md
├── .gitignore
├── .env.example
├── .python-version
├── src/
│   └── <package_name>/
│       ├── __init__.py
│       └── core.py
└── tests/
    ├── __init__.py
    └── test_core.py
```

**src/<package_name>/__init__.py の内容：**
```python
from <package_name>.core import greet


def main() -> None:
    """エントリポイント（`uv run <project-name>` で実行される）"""
    print(greet("FDE"))


if __name__ == "__main__":
    main()
```

**src/<package_name>/core.py の内容（ロジックの置き場。テスト対象のサンプル）：**
```python
def greet(name: str) -> str:
    """名前を受け取って挨拶文を返す"""
    return f"Hello, {name}!"
```

**tests/__init__.py：** 空ファイル

**tests/test_core.py の内容：**
```python
from <package_name>.core import greet


def test_greet():
    assert greet("FDE") == "Hello, FDE!"
```

**.env.example の内容：**
```
# このファイルをコピーして .env を作成し、実際の値を設定すること
# cp .env.example .env

# 例: API_KEY=...
```

**.gitignore の確認・追記：** uvが生成済み（`.venv` 等）。以下が無ければ追記する。
```
.env
__pycache__/
*.pyc
.DS_Store
```

**pyproject.toml の調整：** `[project.scripts]` にエントリポイントがあること（uvが追加済み）を確認し、
pytest設定を追記する。
```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
```

**README.md の内容：**
````markdown
# <project-name>

## セットアップ

```bash
uv sync
cp .env.example .env
# .env を編集して必要な値を設定
```

## 実行

```bash
uv run <project-name>      # エントリポイント
uv run python -m <package_name>  # モジュールとして実行
```

## テスト

```bash
uv run pytest
```

## 依存の追加

```bash
uv add <package>          # ランタイム依存
uv add --dev <package>    # 開発依存
```
````

### Step 5: 依存をインストール

```bash
uv add --dev pytest
# --with があれば指定パッケージを追加（例: uv add requests pandas）
uv sync
```

`uv sync` でプロジェクト自身もeditableインストールされ、`tests/` から `<package_name>` を
import できるようになる。

### Step 6: 動作確認

```bash
uv run <project-name>   # "Hello, FDE!" が表示されること
uv run pytest -q        # テストがパスすること
```

両方が成功することを確認する。

### Step 7: 完了報告

以下を伝える：
- 作成したファイル一覧
- 実行コマンド（`uv run <project-name>`）とテストコマンド（`uv run pytest`）
- 次のステップ（`src/<package_name>/core.py` にロジックを書き、`tests/` にテストを足す。
  依存は `uv add` で追加）

## 守ること

- `.env` はコードに含めない。`.env.example` のみ作成する
- `.venv/` はgitに含めない（uv生成の .gitignore 済み）。手動の `venv/` は作らない
- APIキーは絶対にコードや pyproject.toml に書かない
- 依存は `pip install` ではなく `uv add` / `uv sync` で管理する（lockファイル `uv.lock` を生かす）
- ロジックは `src/<package_name>/` に置き、`tests/` から import してテストする
