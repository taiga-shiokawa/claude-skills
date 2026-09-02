# -*- coding: utf-8 -*-
"""mapping.json に従って drawio へスクリーンショットを埋め込み配置する。

usage: python place_shots.py <file.drawio> --mapping mapping.json
                             [--page N] [--max-width 480] [--gap 140]
                             [--no-edge] [--dry-run] [--out FILE]

mapping.json:
{
  "placements": [
    {"shot": "path/to/①xxx.png", "node_id": "n1", "label": "任意のキャプション"},
    {"shot": "path/to/other.png"}            // node_id 省略 = アンカー無し（右列へ）
  ]
}
"""
import argparse
import base64
import json
import os
import shutil
import sys
import time
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from drawio_common import (  # noqa: E402
    setup_stdout_utf8, load_mxfile, get_graph_model, collect_nodes,
    bounding_box, image_size, image_mime, write_mxfile,
)

IMG_STYLE = (
    "shape=image;verticalLabelPosition=bottom;verticalAlign=top;"
    "labelBackgroundColor=#ffffff;fontSize=12;fontColor=#6B7280;"
    "aspect=fixed;imageAspect=0;image=data:{mime},{b64};"
)
EDGE_STYLE = "endArrow=none;dashed=1;html=1;strokeColor=#9CA3AF;strokeWidth=1;"
V_SPACING = 40  # 同じ列内の画像同士の縦の間隔


def main():
    setup_stdout_utf8()
    ap = argparse.ArgumentParser()
    ap.add_argument("drawio")
    ap.add_argument("--mapping", required=True)
    ap.add_argument("--page", type=int, default=0)
    ap.add_argument("--max-width", type=float, default=480.0)
    ap.add_argument("--gap", type=float, default=140.0, help="図の外周と画像列の間隔")
    ap.add_argument("--no-edge", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args()

    with open(args.mapping, encoding="utf-8") as f:
        placements = json.load(f)["placements"]
    if not placements:
        print(json.dumps({"placed": [], "message": "placements が空です"}, ensure_ascii=False))
        return

    tree = load_mxfile(args.drawio)
    diagram, model, was_compressed = get_graph_model(tree.getroot(), args.page)
    root_el = model.find("root")
    if root_el is None:
        raise ValueError("mxGraphModel/root が見つかりません")

    nodes = collect_nodes(model)
    node_by_id = {n["id"]: n for n in nodes}
    bbox = bounding_box(nodes)
    center_x = (bbox["min_x"] + bbox["max_x"]) / 2

    # ---- 検証と配置サイズの計算 -------------------------------------------
    plans = []
    for p in placements:
        shot = p["shot"]
        if not os.path.isfile(shot):
            raise FileNotFoundError(f"スクショが見つかりません: {shot}")
        node_id = p.get("node_id")
        if node_id and node_id not in node_by_id:
            raise ValueError(f"node_id '{node_id}' は図に存在しません（shot: {shot}）")
        px_w, px_h = image_size(shot)
        w = min(args.max_width, float(px_w))
        h = px_h * (w / px_w)
        anchor = node_by_id.get(node_id) if node_id else None
        side = "right"
        if anchor is not None:
            side = "left" if (anchor["x"] + anchor["w"] / 2) <= center_x else "right"
        plans.append({
            "shot": shot,
            "label": p.get("label") or os.path.splitext(os.path.basename(shot))[0],
            "node_id": node_id,
            "anchor": anchor,
            "side": side,
            "w": w,
            "h": h,
        })

    # ---- 列ごとに y を割り当て（アンカーの y に揃え、重なりは下へ送る） ----
    def sort_key(plan):
        return plan["anchor"]["y"] if plan["anchor"] else float("inf")

    next_y = {"left": None, "right": None}
    for plan in sorted(plans, key=sort_key):
        col = plan["side"]
        desired = plan["anchor"]["y"] if plan["anchor"] else (
            next_y[col] if next_y[col] is not None else bbox["min_y"]
        )
        y = desired if next_y[col] is None else max(desired, next_y[col])
        next_y[col] = y + plan["h"] + V_SPACING
        plan["y"] = y
        plan["x"] = (
            bbox["min_x"] - args.gap - plan["w"] if col == "left"
            else bbox["max_x"] + args.gap
        )

    if args.dry_run:
        print(json.dumps({
            "dry_run": True,
            "bbox": bbox,
            "plan": [
                {k: p[k] for k in ("shot", "label", "node_id", "side", "x", "y", "w", "h")}
                for p in plans
            ],
        }, ensure_ascii=False, indent=2))
        return

    # ---- バックアップ ------------------------------------------------------
    out_path = args.out or args.drawio
    backup = None
    if os.path.abspath(out_path) == os.path.abspath(args.drawio):
        backup = f"{args.drawio}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(args.drawio, backup)

    # ---- セルを追加 --------------------------------------------------------
    stamp = int(time.time())
    placed = []
    for i, plan in enumerate(plans):
        with open(plan["shot"], "rb") as f:
            b64 = base64.b64encode(f.read()).decode("ascii")
        img_id = f"shot-{stamp}-{i}"
        img = ET.SubElement(root_el, "mxCell", {
            "id": img_id,
            "value": plan["label"],
            "style": IMG_STYLE.format(mime=image_mime(plan["shot"]), b64=b64),
            "vertex": "1",
            "parent": "1",
        })
        ET.SubElement(img, "mxGeometry", {
            "x": str(round(plan["x"], 2)),
            "y": str(round(plan["y"], 2)),
            "width": str(round(plan["w"], 2)),
            "height": str(round(plan["h"], 2)),
            "as": "geometry",
        })
        if plan["node_id"] and not args.no_edge:
            edge = ET.SubElement(root_el, "mxCell", {
                "id": f"{img_id}-edge",
                "style": EDGE_STYLE,
                "edge": "1",
                "parent": "1",
                "source": img_id,
                "target": plan["node_id"],
            })
            ET.SubElement(edge, "mxGeometry", {"relative": "1", "as": "geometry"})
        placed.append({
            "shot": plan["shot"],
            "cell_id": img_id,
            "node_id": plan["node_id"],
            "side": plan["side"],
            "x": round(plan["x"], 1),
            "y": round(plan["y"], 1),
            "w": round(plan["w"], 1),
            "h": round(plan["h"], 1),
        })

    write_mxfile(tree, diagram, model, was_compressed, out_path)
    print(json.dumps({
        "placed": placed,
        "backup": backup,
        "out": os.path.abspath(out_path),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
