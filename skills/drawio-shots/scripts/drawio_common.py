# -*- coding: utf-8 -*-
"""drawio-shots 共通処理：drawio の読み書き・座標解決・画像サイズ取得。標準ライブラリのみ。"""
import base64
import html
import re
import struct
import sys
import unicodedata
import urllib.parse
import xml.etree.ElementTree as ET
import zlib


def setup_stdout_utf8():
    """Windows コンソール (cp932) での文字化け・UnicodeEncodeError を防ぐ。"""
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


# ---------------------------------------------------------------- drawio I/O

def load_mxfile(path):
    """mxfile ツリーを返す。"""
    tree = ET.parse(path)
    root = tree.getroot()
    if root.tag != "mxfile":
        # 単体の mxGraphModel だけのファイルもまれにある
        if root.tag == "mxGraphModel":
            return tree
        raise ValueError(f"drawio ファイルではありません（ルート要素: {root.tag}）")
    return tree


def decompress_diagram_text(text):
    """圧縮保存された diagram テキストを mxGraphModel の XML 文字列に展開する。"""
    data = base64.b64decode(text)
    xml_str = urllib.parse.unquote(zlib.decompress(data, -15).decode("utf-8"))
    return xml_str


def get_graph_model(mxfile_root, page_index):
    """指定ページの (diagram要素, mxGraphModel要素, was_compressed) を返す。

    mxfile_root が mxGraphModel そのものの場合は diagram=None。
    """
    if mxfile_root.tag == "mxGraphModel":
        return None, mxfile_root, False
    diagrams = mxfile_root.findall("diagram")
    if not diagrams:
        raise ValueError("diagram 要素が見つかりません")
    if page_index < 0 or page_index >= len(diagrams):
        raise ValueError(f"ページ {page_index} は存在しません（全 {len(diagrams)} ページ）")
    diagram = diagrams[page_index]
    model = diagram.find("mxGraphModel")
    if model is not None:
        return diagram, model, False
    # 圧縮形式：diagram のテキストが deflate+base64
    text = (diagram.text or "").strip()
    if not text:
        raise ValueError(f"ページ {page_index} の内容が空です")
    model = ET.fromstring(decompress_diagram_text(text))
    return diagram, model, True


def list_pages(mxfile_root):
    if mxfile_root.tag == "mxGraphModel":
        return [{"index": 0, "name": "(single model)"}]
    return [
        {"index": i, "name": d.get("name", f"Page-{i + 1}")}
        for i, d in enumerate(mxfile_root.findall("diagram"))
    ]


def write_mxfile(tree, diagram, model, was_compressed, out_path):
    """圧縮ページだった場合は非圧縮の mxGraphModel に置き換えて保存する。"""
    if was_compressed and diagram is not None:
        diagram.text = None
        for child in list(diagram):
            diagram.remove(child)
        diagram.append(model)
    tree.write(out_path, encoding="utf-8", xml_declaration=True)


# ---------------------------------------------------------------- セル走査

def iter_cells(model):
    """(cell要素, ラベル, ホスト要素) を返す。<object>/<UserObject> ラップにも対応。

    ホスト要素 = id/label を持つ外側の要素（ラップが無ければ mxCell 自身）。
    """
    root = model.find("root")
    if root is None:
        return
    for el in list(root):
        if el.tag == "mxCell":
            yield el, el.get("value", ""), el
        elif el.tag in ("object", "UserObject"):
            cell = el.find("mxCell")
            if cell is not None:
                yield cell, el.get("label", el.get("value", "")), el


def get_geometry(cell):
    g = cell.find("mxGeometry")
    if g is None:
        return None
    try:
        return {
            "x": float(g.get("x", 0)),
            "y": float(g.get("y", 0)),
            "w": float(g.get("width", 0)),
            "h": float(g.get("height", 0)),
        }
    except (TypeError, ValueError):
        return None


def collect_nodes(model):
    """頂点セルを絶対座標つきで収集する。戻り値: list[dict]"""
    by_id = {}
    order = []
    for cell, label, host in iter_cells(model):
        cid = host.get("id") or cell.get("id")
        if not cid:
            continue
        by_id[cid] = {
            "cell": cell,
            "label": label,
            "parent": cell.get("parent"),
            "vertex": cell.get("vertex") == "1",
            "geom": get_geometry(cell),
        }
        order.append(cid)

    def abs_pos(cid, _seen=None):
        _seen = _seen or set()
        info = by_id.get(cid)
        if info is None or info["geom"] is None:
            return 0.0, 0.0
        x, y = info["geom"]["x"], info["geom"]["y"]
        pid = info["parent"]
        if pid and pid in by_id and pid not in _seen and pid not in ("0", "1"):
            _seen.add(cid)
            px, py = abs_pos(pid, _seen)
            x += px
            y += py
        return x, y

    nodes = []
    for cid in order:
        info = by_id[cid]
        if not info["vertex"] or info["geom"] is None:
            continue
        ax, ay = abs_pos(cid)
        style = info["cell"].get("style", "") or ""
        nodes.append({
            "id": cid,
            "label": plain_label(info["label"]),
            "raw_label": info["label"],
            "x": ax,
            "y": ay,
            "w": info["geom"]["w"],
            "h": info["geom"]["h"],
            "is_image": ("shape=image" in style or "image=data:" in style),
        })
    return nodes


def bounding_box(nodes):
    boxes = [n for n in nodes if n["w"] > 0 or n["h"] > 0]
    if not boxes:
        return {"min_x": 0, "min_y": 0, "max_x": 800, "max_y": 600}
    return {
        "min_x": min(n["x"] for n in boxes),
        "min_y": min(n["y"] for n in boxes),
        "max_x": max(n["x"] + n["w"] for n in boxes),
        "max_y": max(n["y"] + n["h"] for n in boxes),
    }


# ---------------------------------------------------------------- ラベル正規化

_TAG_RE = re.compile(r"<[^>]+>")


def plain_label(value):
    """HTML タグ・実体参照を除去した表示ラベル。"""
    if not value:
        return ""
    text = html.unescape(value)
    text = _TAG_RE.sub(" ", text)
    return re.sub(r"\s+", " ", text).strip()


def norm(text):
    """マッチング用正規化：NFKC（丸数字→数字・全角→半角）＋小文字＋空白除去。"""
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text).lower()
    return re.sub(r"\s+", "", text)


_LEAD_NUM_RE = re.compile(r"^\D{0,2}?(\d{1,3})")


def leading_number(text):
    """正規化済み文字列の先頭付近にある数字を返す（無ければ None）。"""
    m = _LEAD_NUM_RE.match(text)
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------- 画像サイズ

def image_size(path):
    """PNG / JPEG のピクセルサイズ (w, h) を返す。"""
    with open(path, "rb") as f:
        head = f.read(32)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", head[16:24])
            return int(w), int(h)
        if head[:2] == b"\xff\xd8":  # JPEG
            f.seek(2)
            while True:
                marker = f.read(2)
                if len(marker) < 2 or marker[0] != 0xFF:
                    break
                code = marker[1]
                if code in (0xD8, 0x01) or 0xD0 <= code <= 0xD7:
                    continue
                seg_len = struct.unpack(">H", f.read(2))[0]
                if 0xC0 <= code <= 0xCF and code not in (0xC4, 0xC8, 0xCC):
                    data = f.read(5)
                    h, w = struct.unpack(">HH", data[1:5])
                    return int(w), int(h)
                f.seek(seg_len - 2, 1)
    raise ValueError(f"PNG/JPEG として読めません: {path}")


def image_mime(path):
    lower = path.lower()
    if lower.endswith(".png"):
        return "image/png"
    if lower.endswith((".jpg", ".jpeg")):
        return "image/jpeg"
    raise ValueError(f"対応していない画像形式です（png/jpg のみ）: {path}")
