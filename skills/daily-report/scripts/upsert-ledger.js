'use strict';
// upsert-ledger.js <xlsx> <data.json> — 管理台帳「日誌一覧」へ1日1行で upsert する。
//
// data.json:
//   {
//     "date":    "2026-08-13",          // 必須。この日付の行を探す
//     "project": "案件名",               // C列
//     "summary": "主な作業内容の要約",    // D列
//     "issues":  "課題・懸念",            // F列
//     "tomorrow":"翌日の予定",            // G列
//     "link":    "Wordファイルのパス"     // I列
//   }
//
// 動作:
//   - A列がその日付の行があれば、その行を更新する（レコードは増やさない）。
//     JSON に無いキーの列は元の値を保持する（部分更新できる）。
//   - 無ければ A列が空の最初の行に書く。空行も無ければ表の下に1行伸ばす
//     （dimension と table ref も追随させる）。
//   - B列（曜日）・H列（ファイル名）の数式には触れない。既存数式を保持し、
//     行を伸ばすときだけ正しい行番号で数式を新設する。キャッシュ値は捨て、
//     workbook.xml の calcPr に fullCalcOnLoad="1" を立てて Excel に再計算させる。
//   - E列（進捗率）は本人にしか分からない値なので書かない。既存値は保持する。
const fs = require('fs');
const { readEntry, replaceEntries } = require('./ziptool.js');

const xlsx = process.argv[2];
const dataFile = process.argv[3];
if (!xlsx || !dataFile) { console.error('usage: node upsert-ledger.js <xlsx> <data.json>'); process.exit(1); }

const data = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
if (!/^\d{4}-\d{2}-\d{2}$/.test(data.date || '')) {
  console.error('ERROR: data.date must be "YYYY-MM-DD"'); process.exit(1);
}
const [Y, M, D] = data.date.split('-').map(Number);
const serial = Math.round((Date.UTC(Y, M - 1, D) - Date.UTC(1899, 11, 30)) / 86400000);

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

let sheet = readEntry(xlsx, 'xl/worksheets/sheet1.xml').toString('utf8');

// ── 行の収集 ────────────────────────────────────────────────────────────
const rows = [];
{
  const re = /<row\b[^>]*>[\s\S]*?<\/row>|<row\b[^>]*\/>/g;
  let m;
  while ((m = re.exec(sheet)) !== null) {
    const r = +(/<row\b[^>]*\sr="(\d+)"/.exec(m[0]) || [0, 0])[1];
    rows.push({ r, start: m.index, raw: m[0] });
  }
}
if (!rows.length) { console.error('ERROR: no rows found in sheet1'); process.exit(1); }

function cellsOf(rowRaw) {
  const map = {};
  for (const c of rowRaw.match(/<c\b[^>]*\/>|<c\b[^>]*>[\s\S]*?<\/c>/g) || []) {
    const ref = (/\sr="([A-Z]+)(\d+)"/.exec(c) || [])[1];
    if (ref) map[ref] = c;
  }
  return map;
}
const vOf = c => c ? (/<v>([\s\S]*?)<\/v>/.exec(c) || [])[1] : undefined;
const sAttrOf = (c, def) => {
  const s = c ? (/\ss="(\d+)"/.exec(c) || [])[1] : undefined;
  const v = s !== undefined ? s : def;
  return v === undefined || v === null ? '' : ` s="${v}"`;
};
const fOf = c => c ? (/<f\b[^>]*>[\s\S]*?<\/f>/.exec(c) || [])[0] : undefined;

// ── 対象行の決定 ─────────────────────────────────────────────────────────
let mode = null, target = null;
for (const row of rows) {
  if (row.r < 2) continue;
  if (vOf(cellsOf(row.raw).A) === String(serial)) { mode = 'update'; target = row; break; }
}
if (!mode) {
  for (const row of rows) {
    if (row.r < 2) continue;
    const a = cellsOf(row.raw).A;
    if (!a || vOf(a) === undefined) { mode = 'insert'; target = row; break; }
  }
}
if (!mode) { mode = 'extend'; target = rows[rows.length - 1]; }

const newR = (mode === 'extend') ? target.r + 1 : target.r;
const existing = (mode === 'extend') ? {} : cellsOf(target.raw);

// ── 行の再構築（列順 A..I を保証する）───────────────────────────────────
const DEF_S = { A: '1', B: '2', C: '3', D: '4', E: '5', F: '4', G: '4', H: null, I: '4' };
const FIELD_COL = { project: 'C', summary: 'D', issues: 'F', tomorrow: 'G', link: 'I' };

const inline = (col, text) =>
  `<c r="${col}${newR}"${sAttrOf(existing[col], DEF_S[col])} t="inlineStr"><is><t xml:space="preserve">${esc(text)}</t></is></c>`;
const styleOnly = col => `<c r="${col}${newR}"${sAttrOf(existing[col], DEF_S[col])}/>`;

const defaultF = {
  B: `<f>IF(A${newR}="","",TEXT(A${newR},"aaa"))</f>`,
  H: `<f>IF(A${newR}="","",TEXT(A${newR},"yyyymmdd")&amp;"_開発日誌.docx")</f>`
};
const formulaCell = col => {
  const f = (mode !== 'extend' && fOf(existing[col])) || defaultF[col];
  return `<c r="${col}${newR}"${sAttrOf(existing[col], DEF_S[col])}>${f}</c>`;
};

const wrote = [];
const cells = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'].map(col => {
  if (col === 'A') return `<c r="A${newR}"${sAttrOf(existing.A, DEF_S.A)}><v>${serial}</v></c>`;
  if (col === 'B' || col === 'H') return formulaCell(col);
  if (col === 'E') {
    // 進捗率は書かない。update/insert では既存セルをそのまま残す
    return (mode !== 'extend' && existing.E) ? existing.E : styleOnly('E');
  }
  const field = Object.keys(FIELD_COL).find(k => FIELD_COL[k] === col);
  if (data[field] !== undefined) { wrote.push(field); return inline(col, data[field]); }
  return (mode !== 'extend' && existing[col]) ? existing[col] : styleOnly(col);
}).join('');

// 行タグの属性は元の行から引き継ぐ（spans 等）。r だけ差し替える
let rowAttrs = (/^<row\b([^>]*?)\/?>/.exec(target.raw) || ['', ''])[1];
rowAttrs = rowAttrs.replace(/\sr="\d+"/, ` r="${newR}"`);
const newRow = `<row${rowAttrs}>${cells}</row>`;

if (mode === 'extend') {
  const end = target.start + target.raw.length;
  sheet = sheet.slice(0, end) + newRow + sheet.slice(end);
} else {
  sheet = sheet.slice(0, target.start) + newRow + sheet.slice(target.start + target.raw.length);
}

// ── dimension / table ref の追随 ────────────────────────────────────────
const changes = {};
sheet = sheet.replace(/<dimension ref="A1:([A-Z]+)(\d+)"\/>/, (m0, col, r) =>
  `<dimension ref="A1:${col}${Math.max(+r, newR)}"/>`);
changes['xl/worksheets/sheet1.xml'] = sheet;

try {
  let table = readEntry(xlsx, 'xl/tables/table1.xml').toString('utf8');
  const cur = +((/ref="A1:[A-Z]+(\d+)"/.exec(table) || [])[1] || 0);
  if (newR > cur && cur > 0) {
    table = table.replace(/ref="A1:([A-Z]+)\d+"/g, (m0, col) => `ref="A1:${col}${newR}"`);
    changes['xl/tables/table1.xml'] = table;
  }
} catch (e) { /* テーブル定義なしでも続行 */ }

// ── fullCalcOnLoad（Excel に数式を再計算させる）─────────────────────────
let wb = readEntry(xlsx, 'xl/workbook.xml').toString('utf8');
if (!/fullCalcOnLoad/.test(wb)) {
  if (/<calcPr\b/.test(wb)) wb = wb.replace(/<calcPr\b/, '<calcPr fullCalcOnLoad="1"');
  else wb = wb.replace('</workbook>', '<calcPr fullCalcOnLoad="1"/></workbook>');
  changes['xl/workbook.xml'] = wb;
}

replaceEntries(xlsx, changes);
console.log(JSON.stringify({ ok: true, mode, row: newR, serial, wrote }));
