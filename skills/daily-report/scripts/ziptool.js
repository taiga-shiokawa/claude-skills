'use strict';
// ziptool.js — docx/xlsx (ZIP) の読み書きを Node だけで行う。
//
// なぜ PowerShell の ZipFile を使わないか:
//   - .NET の CreateFromDirectory はエントリ名をバックスラッシュで書き、
//     ZIP 仕様違反となって Word/Excel が開けないファイルを作る。
//   - PowerShell 5.1 は BOM 無し UTF-8 の .ps1 を ANSI として読むため、
//     日本語を含むスクリプトが文字化けして事故になる。
//   Node は両方の問題と無縁なので、ZIP 処理はすべてここに集約する。
const fs = require('fs');
const zlib = require('zlib');

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

// ZIP 全エントリを { name, data(Buffer), dosTime, dosDate } の配列で返す
function readZip(zipPath) {
  const buf = fs.readFileSync(zipPath);
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('EOCD not found (not a zip?): ' + zipPath);
  const count = buf.readUInt16LE(eocd + 10);
  const cdOff = buf.readUInt32LE(eocd + 16);
  const entries = [];
  let p = cdOff;
  for (let i = 0; i < count; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('bad central header @' + p);
    const method  = buf.readUInt16LE(p + 10);
    const dosTime = buf.readUInt16LE(p + 12);
    const dosDate = buf.readUInt16LE(p + 14);
    const csize   = buf.readUInt32LE(p + 20);
    const usize   = buf.readUInt32LE(p + 24);
    const nameLen  = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const cmtLen   = buf.readUInt16LE(p + 32);
    const lho = buf.readUInt32LE(p + 42);
    const name = buf.slice(p + 46, p + 46 + nameLen).toString('utf8');
    if (buf.readUInt32LE(lho) !== 0x04034b50) throw new Error('bad local header for ' + name);
    const lNameLen  = buf.readUInt16LE(lho + 26);
    const lExtraLen = buf.readUInt16LE(lho + 28);
    const dataOff = lho + 30 + lNameLen + lExtraLen;
    const cdata = buf.slice(dataOff, dataOff + csize);
    let data;
    if (method === 0) data = Buffer.from(cdata);
    else if (method === 8) data = zlib.inflateRawSync(cdata);
    else throw new Error('unsupported compression method ' + method + ' for ' + name);
    if (data.length !== usize) throw new Error('size mismatch for ' + name);
    entries.push({ name, data, dosTime, dosDate });
    p += 46 + nameLen + extraLen + cmtLen;
  }
  return entries;
}

// エントリ配列から ZIP を書き出す。エントリ名は常にスラッシュ区切りのまま書く
function writeZip(zipPath, entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const e of entries) {
    if (e.name.includes('\\')) throw new Error('entry name must use forward slashes: ' + e.name);
    const nameBuf = Buffer.from(e.name, 'utf8');
    const comp = zlib.deflateRawSync(e.data, { level: 9 });
    const useComp = comp.length < e.data.length;
    const payload = useComp ? comp : e.data;
    const method = useComp ? 8 : 0;
    const crc = crc32(e.data);
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(20, 4);
    lh.writeUInt16LE(0x0800, 6);          // UTF-8 name flag
    lh.writeUInt16LE(method, 8);
    lh.writeUInt16LE(e.dosTime || 0, 10);
    lh.writeUInt16LE(e.dosDate || 0x5AAD, 12);
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(payload.length, 18);
    lh.writeUInt32LE(e.data.length, 22);
    lh.writeUInt16LE(nameBuf.length, 26);
    lh.writeUInt16LE(0, 28);
    parts.push(lh, nameBuf, payload);

    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE(20, 4);
    ch.writeUInt16LE(20, 6);
    ch.writeUInt16LE(0x0800, 8);
    ch.writeUInt16LE(method, 10);
    ch.writeUInt16LE(e.dosTime || 0, 12);
    ch.writeUInt16LE(e.dosDate || 0x5AAD, 14);
    ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(payload.length, 20);
    ch.writeUInt32LE(e.data.length, 24);
    ch.writeUInt16LE(nameBuf.length, 28);
    ch.writeUInt32LE(offset, 42);
    central.push(ch, nameBuf);
    offset += lh.length + nameBuf.length + payload.length;
  }
  const cdStart = offset;
  let cdLen = 0;
  for (const b of central) cdLen += b.length;
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cdLen, 12);
  eocd.writeUInt32LE(cdStart, 16);
  fs.writeFileSync(zipPath, Buffer.concat([...parts, ...central, eocd]));
}

function readEntry(zipPath, entryName) {
  const e = readZip(zipPath).find(x => x.name === entryName);
  if (!e) throw new Error(entryName + ' not found in ' + zipPath);
  return e.data;
}

// map: { entryName: Buffer|string } を差し替えて ZIP 全体を書き直す
function replaceEntries(zipPath, map) {
  const entries = readZip(zipPath);
  for (const [name, content] of Object.entries(map)) {
    const buf = Buffer.isBuffer(content) ? content : Buffer.from(content, 'utf8');
    const e = entries.find(x => x.name === name);
    if (e) e.data = buf;
    else entries.push({ name, data: buf, dosTime: 0, dosDate: 0x5AAD });
  }
  writeZip(zipPath, entries);
}

module.exports = { readZip, writeZip, readEntry, replaceEntries, crc32 };

if (require.main === module) {
  const [cmd, zip, a, b] = process.argv.slice(2);
  try {
    if (cmd === 'list') {
      for (const e of readZip(zip)) console.log(e.name + '\t' + e.data.length + 'B');
    } else if (cmd === 'read') {
      process.stdout.write(readEntry(zip, a));
    } else if (cmd === 'replace') {
      replaceEntries(zip, { [a]: fs.readFileSync(b) });
      console.log('replaced ' + a + ' in ' + zip);
    } else {
      console.log('usage: node ziptool.js list <zip> | read <zip> <entry> | replace <zip> <entry> <srcFile>');
      process.exit(1);
    }
  } catch (e) { console.error('ERROR: ' + e.message); process.exit(1); }
}
