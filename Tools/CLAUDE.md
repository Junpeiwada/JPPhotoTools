# Tools/ — 共通ツール置き場

リポジトリ横断で使う補助ツールを置く。ここのツールはアプリ本体（`App/` / `Packages/`）には依存させない。

---

## 共通 venv 方針

ツールが増えても依存管理を分散させないため、Python 依存は **`Tools/.venv` に一括**で持つ。ツールごとに個別 venv は作らず、この共通 venv を全ツールで共有する。

```bash
# 初回セットアップ（.venv は Git 管理外なのでマシンごとに作成する）
python3 -m venv Tools/.venv
# 共通依存が必要になったら requirements.txt にまとめて一括インストール
# Tools/.venv/bin/pip install -r Tools/requirements.txt
```

- `Tools/.venv` は `.gitignore`（`.venv/` パターン）で除外する。コミットしない
- 標準ライブラリのみで動くツールは venv 不要。システム Python の差異を避けたい場合は共通 venv の Python で実行してよい
- 共通で必要な依存が出てきたら `Tools/requirements.txt` を作って追記し、上記コマンドでインストールする

## 現在のツール

| ツール | 内容 | venv |
|---|---|---|
| `GenDocsToc/` | Markdown の「## 変更履歴」直後（無ければ「# タイトル」直後）に目次（## 目次）を生成・更新 | 不要（標準ライブラリのみ） |
| `release.sh` | ローカルから 1 コマンドでリリースを発火（バージョン更新 → コミット → タグ push → Actions 起動） | 不要（bash） |

### GenDocsToc の使い方

```bash
python3 Tools/GenDocsToc/gen_toc.py <target.md>            # 目次を生成・更新
python3 Tools/GenDocsToc/gen_toc.py --dry-run <target.md>  # 差分確認（書き込まない）
```

詳細は [GenDocsToc/README.md](GenDocsToc/README.md) を参照。

### release.sh の使い方

```bash
Tools/release.sh 1.2.0        # App/project.yml のバージョン更新 → コミット → タグ v1.2.0 を push
Tools/release.sh 1.2.0 -y     # 確認プロンプトを省略
Tools/release.sh --help       # 詳細

# ルートの package.json 経由（VSCode の NPM SCRIPTS パネルからも実行可）
npm run release -- 1.2.0      # バージョンを渡して発火
npm run release               # 引数なし。端末ならバージョンを対話入力
```

push により GitHub Actions の Release ワークフロー（署名・公証・配布・appcast 更新）が発火する。
ワーキングツリーが汚れている／タグが既存の場合は中断する。詳細は [../Docs/リリース手順.md](../Docs/リリース手順.md)。
