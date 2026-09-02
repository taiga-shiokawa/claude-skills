'use strict';
// read-ledger.js <xlsx> — 管理台帳の「日誌一覧」シートを行ごとに表示する。
// upsert-ledger.js の実行前後の確認に使う。sharedStrings / inlineStr の両方を解決する。
const { readZip } = require('./ziptool.js');

const xlsx = process.argv[2];
if (!xlsx) { console.error('usage: node read-ledger.js <xlsx>'); process.exit(1); }

const entries = readZip(xlsx);
const get = name => { const e = entries.find(x => x.name === name); return e ? e.data.toString('utf8') : null; };
const unesc = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

const shared = [];
const ss = get('xl/sharedStrings.xml');
if (ss) {
  for (const si of ss.match(/<si>[\s\S]*?<\/si>/g) || []) {
    const ts = si.match(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g) || [];
    shared.push(ts.map(t => unesc(t.replace(/<[^>]+>/g, ''))).join(''));
  }
}

const sheet = get('xl/worksheets/sheet1.xml');
if (!sheet) { console.error('ERROR: xl/worksheets/sheet1.xml not found'); process.exit(1); }

const rows = sheet.match(/<row\b[^>]*>[\s\S]*?<\/row>|<row\b[^>]*\/>/g) || [];
for (const row of rows) {
  const rnum = (/<row\b[^>]*\sr="(\d+)"/.exec(row) || [])[1] || '?';
  const cells = row.match(/<c\b[^>]*\/>|<c\b[^>]*>[\s\S]*?<\/c>/g) || [];
  const out = [];
  for (const c of cells) {
    const ref = (/\sr="([A-Z]+\d+)"/.exec(c) || [])[1] || '?';
    const t = (/\st="([^"]+)"/.exec(c) || [])[1] || 'n';
    const fm = /<f\b[^>]*>([\s\S]*?)<\/f>/.exec(c);
    let val = '';
    if (t === 'inlineStr') {
      const ts = c.match(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g) || [];
      val = ts.map(x => unesc(x.replace(/<[^>]+>/g, ''))).join('');
    } else {
      const v = /<v>([\s\S]*?)<\/v>/.exec(c);
      if (v) val = (t === 's') ? (shared[+v[1]] !== undefined ? shared[+v[1]] : '?s' + v[1]) : unesc(v[1]);
    }
    if (fm) val = '=' + unesc(fm[1]) + (val !== '' ? '  -> ' + val : '');
    if (val !== '') out.push(ref + ': ' + val);
  }
  if (out.length) console.log('r' + rnum + '  ' + out.join('  |  '));
}

const dim = (/<dimension ref="([^"]*)"/.exec(sheet) || [])[1];
console.log('dimension: ' + dim);
const table = get('xl/tables/table1.xml');
if (table) console.log('table ref: ' + ((/\sref="([^"]*)"/.exec(table) || [])[1] || '?'));
