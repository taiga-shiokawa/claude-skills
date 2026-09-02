# -*- coding: utf-8 -*-
"""drawio ファイルを解析し、ノード一覧・スクショ一覧・ファイル名規約による自動マッチングを JSON で出力する。

usage: python inspect_drawio.py <file.drawio> [--shots DIR] [--page N]
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from drawio_common import (  # noqa: E402
    setup_stdout_utf8, load_mxfile, get_graph_model, list_pages,
    collect_nodes, bounding_box, norm, leading_number, image_size,
)

SHOT_EXTS = (".png", ".jpg", ".jpeg")


def tokenize(stem):
    """ファイル名の語幹をマッチング用トークンに分解する。"""
    tokens = [t for t in re.split(r"[_\-\s]+", stem) if t]
    # 語幹全体もトークンとして試す（区切りが無いケース）
    if stem not in tokens:
        tokens.append(stem)
    return tokens


def match_shot(stem, nodes):
    """1枚のスクショをノードへマッチングする。

    戻り値: (matches: list[node], method: str)
      method は "number"（先頭数字一致）か "substring"（部分一致）。
    """
    nstem = norm(stem)

    # 規約1: 先頭数字（①/1/02 など。NFKC 正規化で丸数字も数字になる）
    num = leading_number(nstem)
    if num is not None:
        hits = [n for n in nodes if leading_number(norm(n["label"])) == num]
        if hits:
            return hits, "number"

    # 規約2: トークンの部分一致（長いトークン優先。2文字以上のみ）
    tokens = sorted({norm(t) for t in tokenize(stem)}, key=len, reverse=True)
    for tok in tokens:
        if len(tok) < 2 or tok.isdigit():
            continue
        hits = [n for n in nodes if tok in norm(n["label"])]
        if hits:
            return hits, "substring"
    return [], "none"


def main():
    setup_stdout_utf8()
    ap = argparse.ArgumentParser()
    ap.add_argument("drawio")
    ap.add_argument("--shots", help="スクリーンショットのフォルダ")
    ap.add_argument("--page", type=int, default=0)
    args = ap.parse_args()

    tree = load_mxfile(args.drawio)
    root = tree.getroot()
    diagram, model, was_compressed = get_graph_model(root, args.page)

    all_nodes = collect_nodes(model)
    label_nodes = [n for n in all_nodes if n["label"] and not n["is_image"]]
    existing_images = sum(1 for n in all_nodes if n["is_image"])

    result = {
        "file": os.path.abspath(args.drawio),
        "pages": list_pages(root),
        "page": args.page,
        "compressed": was_compressed,
        "bbox": bounding_box(all_nodes),
        "existing_images": existing_images,
        "nodes": [
            {k: n[k] for k in ("id", "label", "x", "y", "w", "h")}
            for n in label_nodes
        ],
    }

    if args.shots:
        shots, auto_matches, ambiguous, unmatched = [], [], [], []
        for name in sorted(os.listdir(args.shots)):
            if not name.lower().endswith(SHOT_EXTS):
                continue
            path = os.path.join(args.shots, name)
            try:
                w, h = image_size(path)
            except ValueError as e:
                shots.append({"file": name, "error": str(e)})
                continue
            shots.append({"file": name, "width": w, "height": h})

            stem = os.path.splitext(name)[0]
            hits, method = match_shot(stem, label_nodes)
            if len(hits) == 1:
                auto_matches.append({
                    "shot": name,
                    "node_id": hits[0]["id"],
                    "node_label": hits[0]["label"],
                    "method": method,
                })
            elif len(hits) > 1:
                ambiguous.append({
                    "shot": name,
                    "method": method,
                    "candidates": [
                        {"node_id": n["id"], "node_label": n["label"]} for n in hits
                    ],
                })
            else:
                unmatched.append({"shot": name})

        result.update({
            "shots_dir": os.path.abspath(args.shots),
            "shots": shots,
            "auto_matches": auto_matches,
            "ambiguous": ambiguous,
            "unmatched": unmatched,
        })

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
