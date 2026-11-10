// D1 de mentira sobre node:sqlite, solo para los tests.
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';

class Stmt {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    return new Stmt(this.db, this.sql, args);
  }
  _p() {
    return this.db.prepare(this.sql);
  }
  async first() {
    const r = this._p().get(...this.args);
    return r ? { ...r } : null;
  }
  async all() {
    return { results: this._p().all(...this.args).map((r) => ({ ...r })) };
  }
  async run() {
    this._p().run(...this.args);
    return { success: true };
  }
}

export function makeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (const f of ['0001_init.sql', '0002_sync.sql']) {
    db.exec(readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8'));
  }
  return {
    prepare: (sql) => new Stmt(db, sql),
    async batch(stmts) {
      db.exec('BEGIN');
      try {
        for (const s of stmts) await s.run();
        db.exec('COMMIT');
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
      return stmts.map(() => ({ success: true }));
    },
  };
}
