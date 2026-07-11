import { randomBytes } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';

const dataDir = '/run/roamarr-secrets';
const path = `${dataDir}/credentials.json`;
mkdirSync(dataDir, { recursive: true });
const stored = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : {};

const values = {
	ROAMARR_SECRET: process.env.ROAMARR_SECRET || stored.ROAMARR_SECRET || randomBytes(32).toString('base64'),
	DATABASE_USER: process.env.DATABASE_USER || stored.DATABASE_USER || `roamarr_${randomBytes(6).toString('hex')}`,
	DATABASE_PASS: process.env.DATABASE_PASS || stored.DATABASE_PASS || randomBytes(32).toString('base64url')
};

const temporary = `${path}.tmp`;
writeFileSync(temporary, JSON.stringify(values), { mode: 0o600 });
chmodSync(temporary, 0o600);
renameSync(temporary, path);
Object.assign(process.env, values);
console.log('Roamarr secrets ready from persistent secret storage.');
await import('./build/index.js');
