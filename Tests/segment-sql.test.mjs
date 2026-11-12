import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

// Execute the application's SQL against a disposable database, not user data.
// This checks SQL contracts only; Swift bindings still need an iOS build.
const root = new URL('../', import.meta.url);
const sources = Object.fromEntries(['Store.swift', 'Store+Ext.swift', 'Store+Memory.swift'].map(name => [
  name, readFileSync(new URL(`TaoSheng/Core/${name}`, root), 'utf8'),
]));

function createTable(db, name) {
  const source = Object.values(sources).join('\n');
  const sql = source.match(new RegExp(`CREATE TABLE IF NOT EXISTS ${name} \\([\\s\\S]*?\\);`))?.[0];
  assert.ok(sql, `Missing ${name} schema`);
  db.exec(sql);
}

function migrateSegments(db) {
  for (const source of Object.values(sources)) {
    for (const match of source.matchAll(/ensureColumn\(table: "segment", column: "([^"]+)", ddl: "([^"]+)"\)/g)) {
      const columns = db.prepare('PRAGMA table_info(segment)').all();
      if (!columns.some(column => column.name === match[1])) db.exec(match[2]);
    }
  }
}

function sqlIn(file, name) {
  const source = sources[file];
  const start = source.indexOf(`    func ${name}(`);
  assert.notEqual(start, -1, `Missing ${name}`);
  const body = source.slice(start).split(/\n    (?:private )?func /)[0];
  const sql = body.match(/(?:let|var) sql = """([\s\S]*?)"""/)?.[1]
    ?? body.match(/(?:let|var) sql = "([^"\n]+)"/)?.[1];
  assert.ok(sql, `Missing SQL in ${name}`);
  return sql.replaceAll('\\(limit)', '100').replaceAll('\\(min(limit * 4, 80))', '80')
    .replaceAll('\\(clauses)', 'transcript LIKE ?');
}

function fixture() {
  const db = new DatabaseSync(':memory:');
  createTable(db, 'segment');
  migrateSegments(db);
  const insert = db.prepare(sqlIn('Store.swift', 'insert'));
  for (const [index, mode] of ['daily', 'meeting', 'training', 'call'].entries()) {
    insert.run(mode, 100 + index, 110 + index, 10, `${mode}.wav`, 320000,
      `测试 ${mode}`, '', 'transcribed', '2026-11-12', 110 + index, mode);
  }
  insert.run('pending', 200, 210, 10, 'pending.wav', 320000, '', '', 'recorded', '2026-11-12', 210, 'meeting');
  db.exec("UPDATE segment SET starred=1 WHERE id='training'");
  return db;
}

test('migration preserves legacy audio and transcripts, defaults mode to daily, and is repeatable', () => {
  const db = new DatabaseSync(':memory:');
  try {
    createTable(db, 'segment');
    db.prepare(`INSERT INTO segment (id,started_at,ended_at,duration,file_name,transcript,day,created_at)
      VALUES (?,?,?,?,?,?,?,?)`).run('legacy', 1, 11, 10, 'old.wav', '历史原话', '2026-11-11', 11);
    migrateSegments(db);
    migrateSegments(db);
    const row = db.prepare('SELECT file_name,transcript,capture_mode FROM segment WHERE id=?').get('legacy');
    assert.deepEqual({ ...row }, { file_name: 'old.wav', transcript: '历史原话', capture_mode: 'daily' });
  } finally { db.close(); }
});

test('all segment readers return the persisted mode in the twelfth column', () => {
  const db = fixture();
  try {
    const cases = [
      ['Store.swift', 'segments', [], 'call', 'call'],
      ['Store.swift', 'pendingSegments', [], 'pending', 'meeting'],
      ['Store.swift', 'search', ['%测试%'], 'meeting', 'meeting'],
      ['Store+Ext.swift', 'starredSegments', [], 'training', 'training'],
      ['Store+Ext.swift', 'searchForAsk', ['%测试%'], 'call', 'call'],
      ['Store+Ext.swift', 'recentTranscripts', [0], 'training', 'training'],
      ['Store+Ext.swift', 'segment', ['meeting'], 'meeting', 'meeting'],
      ['Store+Memory.swift', 'undigestedSegments', ['2026-11-12'], 'call', 'call'],
      ['Store+Memory.swift', 'transcriptRows', ['2026-11-12'], 'training', 'training'],
    ];
    for (const [file, name, params, id, mode] of cases) {
      const statement = db.prepare(sqlIn(file, name));
      assert.equal(statement.columns().length, 12, name);
      assert.equal(statement.columns()[11].name, 'capture_mode', name);
      assert.equal(statement.all(...params).find(row => row.id === id)?.capture_mode, mode, name);
    }
    db.prepare('UPDATE segment SET digested=1 WHERE id=?').run('call');
    assert.ok(!db.prepare(sqlIn('Store+Memory.swift', 'undigestedSegments')).all('2026-11-12')
      .some(row => row.id === 'call'));
  } finally { db.close(); }
});

test('backlog spans multiple pages and retains earlier days for scheduled processing', () => {
  const db = fixture();
  try {
    const insert = db.prepare(sqlIn('Store.swift', 'insert'));
    for (let i = 0; i < 201; i += 1) {
      insert.run(`old-${i}`, i, i + 1, 1, `${i}.wav`, 32000,
        '历史原话', '', 'transcribed', '2026-11-11', i + 1, 'daily');
    }
    const days = db.prepare(sqlIn('Store+Memory.swift', 'undigestedDays')).all('2026-11-12');
    assert.deepEqual(days.map(row => row.day), ['2026-11-11', '2026-11-12']);
    const query = sqlIn('Store+Memory.swift', 'undigestedSegments').replace('LIMIT 100', 'LIMIT 200');
    const first = db.prepare(query).all('2026-11-11');
    assert.equal(first.length, 200);
    for (const row of first) db.prepare('UPDATE segment SET digested=1 WHERE id=?').run(row.id);
    assert.equal(db.prepare(query).all('2026-11-11').length, 1);
    db.prepare('UPDATE segment SET digested=1 WHERE id=?').run('old-200');
    assert.equal(db.prepare(query).all('2026-11-11').length, 0);
  } finally { db.close(); }
});

test('completion hints cannot overwrite a user ignored state during a model request', () => {
  const db = new DatabaseSync(':memory:');
  try {
    createTable(db, 'memory_item');
    const insert = db.prepare(`INSERT INTO memory_item
      (id,day,category,content,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)`);
    insert.run('active', '2026-11-12', '待办', '发报告', 'accepted', 100, 100);
    insert.run('changed', '2026-11-12', '待办', '交材料', 'pending', 100, 100);
    db.prepare("UPDATE memory_item SET status='ignored' WHERE id=?").run('changed');
    const update = db.prepare(sqlIn('Store+Memory.swift', 'completeOpenItem'));
    update.run(200, 'active');
    update.run(200, 'changed');
    assert.equal(db.prepare('SELECT status FROM memory_item WHERE id=?').get('active').status, 'done');
    const ignored = db.prepare('SELECT status,updated_at FROM memory_item WHERE id=?').get('changed');
    assert.deepEqual({ ...ignored }, { status: 'ignored', updated_at: 100 });
  } finally { db.close(); }
});

test('recent transcripts filter by time before limit, keeping older rows from crowding out the window', () => {
  const db = fixture();
  try {
    const insert = db.prepare(sqlIn('Store.swift', 'insert'));
    for (let i = 0; i < 110; i += 1) {
      insert.run(`outside-${i}`, -1000 + i, -990 + i, 10, `${i}.wav`, 100,
        '较早原话', '', 'transcribed', '2026-11-11', 1000 + i, 'daily');
    }
    const rows = db.prepare(sqlIn('Store+Ext.swift', 'recentTranscripts').replace('LIMIT 100', 'LIMIT 5')).all(101);
    assert.deepEqual(rows.map(row => row.id), ['call', 'training', 'meeting']);
  } finally { db.close(); }
});

test('wipeAll includes every persisted memory and environment table', () => {
  const source = sources['Store+Ext.swift'];
  const body = source.slice(source.indexOf('    func wipeAll('), source.indexOf('    func searchForAsk('));
  for (const name of ['memory_event', 'memory_item', 'skill_card', 'thing', 'thing_fact', 'env_tag']) {
    assert.match(body, new RegExp(`"${name}"`), `${name} must be erased`);
  }
});

test('reorganized event keeps its identity and user star state', () => {
  const source = sources['Store+Memory.swift'];
  const body = source.slice(source.indexOf('    func upsertEvent('), source.indexOf('    func events('));
  assert.match(body, /bind\(st, 1, eventID\)/);
  assert.match(body, /sqlite3_bind_int\(st, 14, keepStarred \? 1 : 0\)/);
  assert.match(body, /if let s = keepStarredAt \{ sqlite3_bind_double\(st, 15,/);
  const db = new DatabaseSync(':memory:');
  try {
    createTable(db, 'memory_event');
    const insert = db.prepare(sqlIn('Store+Memory.swift', 'upsertEvent'));
    const event = (id, title, starred, starredAt) => [id, '2026-11-12', 100, null, '其他', title,
      '', '[]', '[]', null, '平静', 3, 0, starred, starredAt, 'same-entity', 0, 1, 0, 100];
    insert.run(...event('original', '第一版', 1, 123));
    const existing = db.prepare('SELECT id,starred,starred_at FROM memory_event WHERE entity_id=? AND deleted=0 LIMIT 1')
      .get('same-entity');
    insert.run(...event(existing.id, '第二版', existing.starred, existing.starred_at));
    assert.deepEqual({ ...db.prepare('SELECT id,title,starred,starred_at FROM memory_event').get() },
      { id: 'original', title: '第二版', starred: 1, starred_at: 123 });
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM memory_event').get().n, 1);
  } finally { db.close(); }
});

test('unfinished item context includes real IDs and excludes completed and ignored items', () => {
  const db = new DatabaseSync(':memory:');
  try {
    createTable(db, 'memory_item');
    const insert = db.prepare(`INSERT INTO memory_item
      (id,day,category,content,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)`);
    for (const status of ['pending', 'accepted', 'done', 'ignored']) {
      insert.run(`id-${status}`, '2026-11-12', '待办', `事项 ${status}`, status, 100, 100);
    }
    const rows = db.prepare(sqlIn('Store+Memory.swift', 'openItemContents')).all(0);
    assert.deepEqual(rows.map(row => row.id).sort(), ['id-accepted', 'id-pending']);
    assert.equal(rows.find(row => row.id === 'id-pending')?.content, '事项 pending');
  } finally { db.close(); }
});
