'use strict';
// fill-docx.js <docx> <ops.json> — 段落単位で本文を書き込む。
//
// ops.json は次の配列（index は read-docx.js の通し番号）:
//   { "op": "fill",   "index": 7,  "lines": ["1行目", "", "3行目"] }
//     → 空段落を lines の段落列に置き換える。対象に文字があればエラーで止まる
//       （既存内容を黙って消さないため。既存に足すなら append を使う）。
//   { "op": "append", "index": 44, "lines": ["追記1", "追記2"] }
//     → その段落の直後に、同じ書式（pPr）の段落として lines を挿入する。
//       当日2回目以降の実行で、既に書いた節に追記するときに使う。
//
// 書式は対象段落の pPr を引き継ぐので、表セル内でも見出し直後でも崩れない。
const fs = require('fs');
const { readEntry, replaceEntries } = require('./ziptool.js');

const docx = process.argv[2];
const opsFile = process.argv[3];
if (!docx || !opsFile) { console.error('usage: node fill-docx.js <docx> <ops.json>'); process.exit(1); }

let xml = readEntry(docx, 'word/document.xml').toString('utf8');
const ops = JSON.parse(fs.readFileSync(opsFile, 'utf8'));

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const paras = [];
{
  const re = /<w:p(?:\s[^>]*)?\/>|<w:p(?:\s[^>]*)?>[\s\S]*?<\/w:p>/g;
  let m;
  while ((m = re.exec(xml)) !== null) paras.push({ start: m.index, raw: m[0] });
}

// w14:paraId は文書内で一意であるべき属性なので、複製段落からは落とす
function cleanAttrs(attrs) {
  return attrs.replace(/\sw14:paraId="[^"]*"/, '').replace(/\sw14:textId="[^"]*"/, '');
}

function paraParts(raw) {
  const self = /^<w:p((?:\s[^>]*?)?)\/>$/.exec(raw);
  const attrs = self ? self[1] : /^<w:p((?:\s[^>]*?)?)>/.exec(raw)[1];
  const pprM = /<w:pPr>[\s\S]*?<\/w:pPr>/.exec(raw);
  return { attrs, ppr: pprM ? pprM[0] : '' };
}

function buildParas(raw, lines, keepFirstAttrs) {
  const { attrs, ppr } = paraParts(raw);
  const run = t => t === '' ? '' : `<w:r><w:t xml:space="preserve">${esc(t)}</w:t></w:r>`;
  return lines.map((t, i) => {
    const a = (i === 0 && keepFirstAttrs) ? attrs : cleanAttrs(attrs);
    return `<w:p${a}>${ppr}${run(t)}</w:p>`;
  }).join('');
}

// index の大きい順に適用し、先に処理した箇所のオフセットずれを避ける
const sorted = [...ops].sort((a, b) => b.index - a.index);
let filled = 0, appended = 0;
for (const op of sorted) {
  const p = paras[op.index];
  if (!p) { console.error('ERROR: paragraph index ' + op.index + ' not found (total ' + paras.length + ')'); process.exit(1); }
  if (!Array.isArray(op.lines) || op.lines.length === 0) { console.error('ERROR: op at index ' + op.index + ' has no lines'); process.exit(1); }

  if (op.op === 'fill') {
    if (p.raw.includes('<w:t')) {
      console.error('ERROR: paragraph ' + op.index + ' is not empty. Use "append" to add to existing content.');
      process.exit(1);
    }
    xml = xml.slice(0, p.start) + buildParas(p.raw, op.lines, true) + xml.slice(p.start + p.raw.length);
    filled++;
  } else if (op.op === 'append') {
    const insert = buildParas(p.raw, op.lines, false);
    const end = p.start + p.raw.length;
    xml = xml.slice(0, end) + insert + xml.slice(end);
    appended++;
  } else {
    console.error('ERROR: unknown op "' + op.op + '" (use "fill" or "append")');
    process.exit(1);
  }
}

replaceEntries(docx, { 'word/document.xml': xml });
console.log(JSON.stringify({ ok: true, filled, appended, totalParagraphs: paras.length }));
