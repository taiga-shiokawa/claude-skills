'use strict';
// read-docx.js <docx> — 段落を通し番号つきで一覧する。
// fill-docx.js に渡す index はこの番号。書き込み前後の確認に必ず使う。
const { readEntry } = require('./ziptool.js');

const docx = process.argv[2];
if (!docx) { console.error('usage: node read-docx.js <docx>'); process.exit(1); }

const xml = readEntry(docx, 'word/document.xml').toString('utf8');
const unesc = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

// 表セル内かどうかは、その位置までの <w:tc> 開閉数の差で判定する
const tcOpens = [];
{
  const re = /<w:tc(?:\s[^>]*)?>|<\/w:tc>/g;
  let m;
  while ((m = re.exec(xml)) !== null) tcOpens.push({ pos: m.index, open: m[0][1] !== '/' });
}
function inCell(pos) {
  let depth = 0;
  for (const t of tcOpens) {
    if (t.pos > pos) break;
    depth += t.open ? 1 : -1;
  }
  return depth > 0;
}

const re = /<w:p(?:\s[^>]*)?\/>|<w:p(?:\s[^>]*)?>[\s\S]*?<\/w:p>/g;
let m, i = 0;
while ((m = re.exec(xml)) !== null) {
  const raw = m[0];
  const text = (raw.match(/<w:t(?:\s[^>]*)?>([\s\S]*?)<\/w:t>/g) || [])
    .map(s => unesc(s.replace(/<[^>]+>/g, ''))).join('');
  const style = (/<w:pStyle w:val="([^"]*)"/.exec(raw) || [])[1] || '';
  const tags = [
    inCell(m.index) ? 'cell' : '',
    style ? 'style=' + style : '',
    raw.includes('<w:t') ? '' : 'EMPTY'
  ].filter(Boolean).join(' ');
  console.log('[' + String(i).padStart(3) + '] ' + (tags ? '(' + tags + ') ' : '') + text);
  i++;
}
console.log('total: ' + i + ' paragraphs');
