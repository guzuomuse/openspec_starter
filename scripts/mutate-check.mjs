#!/usr/bin/env node
// 变异测试台：把源文件逐条改坏，看现有断言能不能杀死它（变红）。
//
// 用法：
//   node scripts/mutate-check.mjs <mutations.mjs>
//   node scripts/mutate-check.mjs <mutations.mjs> --cmd "node --test test/x.test.mjs"
//   node scripts/mutate-check.mjs <mutations.mjs> --root . --keep
//
// mutations.mjs 是一个 ESM 文件，默认导出一个数组，每项：
//   { id: "M1", file: "src/roman.mjs", note: "表改成升序", apply: (source) => mutatedSource }
// file 相对 --root（默认当前目录）；apply 必须返回字符串。
//
// 判读：
//   KILLED    改坏了 → 测试变红（这批断言对它有区分力）
//   SURVIVED  改坏了 → 测试仍全绿（这一行/这个分支没有任何断言钉住）
//   NOOP      apply 没改动任何字符（正则没匹配上）——工具用法错误，不能算 KILLED
//
// 一个容易误判的情形：**等价变异**（改了写法、行为没变，例如 `out += x` → `out = out + x`）。
// 它存活是正常的，不是缺口；发现是等价变异就从清单里删掉，别为它硬补断言（那只会写成同义反复）。
//
// 退出码：0 = 基线绿且全部 KILLED；1 = 有 SURVIVED 或 NOOP；2 = 用法错误或基线就是红的。
//
// 设计取舍：
// - 整棵项目复制到临时目录再跑，工作区一个字节都不动。
// - 每条变异跑之前，先把被改的文件还原成基线内容，所以不会互相污染；
//   前提是变异只改一个文件、且测试不写文件（不满足就别用这个工具，手动做）。
// - 基线必须先是绿的：基线红时无法区分"变异被杀死"和"本来就红"。

import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import process from 'node:process';

const USAGE = `用法: node scripts/mutate-check.mjs <mutations.mjs> [--cmd "<测试命令>"] [--root <项目根>] [--keep]`;

const argv = process.argv.slice(2);
const flags = { cmd: 'node --test', root: '.', keep: false };
const positional = [];

for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  if (arg === '--cmd') flags.cmd = argv[++i];
  else if (arg === '--root') flags.root = argv[++i];
  else if (arg === '--keep') flags.keep = true;
  else if (arg === '-h' || arg === '--help') {
    console.log(USAGE);
    process.exit(0);
  } else positional.push(arg);
}

const specPath = positional[0];
if (!specPath) {
  console.error(`✗ 缺少变异清单\n${USAGE}`);
  process.exit(2);
}
if (!flags.cmd) {
  console.error('✗ --cmd 不能为空');
  process.exit(2);
}

const rootDir = resolve(flags.root);
if (!existsSync(rootDir)) {
  console.error(`✗ 项目根不存在：${rootDir}`);
  process.exit(2);
}

let mutations;
try {
  const mod = await import(pathToFileURL(resolve(specPath)).href);
  mutations = mod.default;
} catch (error) {
  console.error(`✗ 读不了变异清单 ${specPath}\n  ${error.message}`);
  process.exit(2);
}

if (!Array.isArray(mutations) || mutations.length === 0) {
  console.error('✗ 变异清单必须导出一个非空数组');
  process.exit(2);
}

for (const [index, mutation] of mutations.entries()) {
  const label = mutation?.id ?? `#${index + 1}`;
  if (typeof mutation?.apply !== 'function' || typeof mutation?.file !== 'string') {
    console.error(`✗ 变异 ${label} 形状不对：需要 { id, file, apply(source) }`);
    process.exit(2);
  }
  if (!existsSync(join(rootDir, mutation.file))) {
    console.error(`✗ 变异 ${label} 指向的文件不存在：${mutation.file}`);
    process.exit(2);
  }
}

// ---- 复制一份干净的副本 -----------------------------------------------------
const SKIP = new Set(['.git', 'node_modules', 'dist', 'build', 'target', '.cache', '.turbo']);
const workDir = mkdtempSync(join(tmpdir(), 'mutate-check-'));

cpSync(rootDir, workDir, {
  recursive: true,
  filter: (src) => !SKIP.has(basename(src)),
});

const run = (cwd) => {
  const result = spawnSync(flags.cmd, {
    cwd,
    shell: true,
    timeout: 300_000,
    encoding: 'utf8',
  });
  if (result.error) return { ok: false, reason: result.error.message };
  return { ok: result.status === 0, code: result.status };
};

console.log(`==> 基线：${flags.cmd}`);
const baseline = run(workDir);
if (!baseline.ok) {
  console.error(
    `✗ 基线就是红的（${baseline.reason ?? `exit ${baseline.code}`}），无法区分"变异被杀死"和"本来就红"。\n` +
      `  先把测试跑绿，再来做变异。副本保留在：${workDir}`,
  );
  process.exit(2);
}
console.log('    绿\n');

// ---- 逐条变异 ---------------------------------------------------------------
const results = [];

for (const mutation of mutations) {
  const pristine = readFileSync(join(rootDir, mutation.file), 'utf8');
  const mutated = mutation.apply(pristine);

  if (typeof mutated !== 'string') {
    results.push({ id: mutation.id, verdict: 'NOOP', note: 'apply 没返回字符串' });
    continue;
  }
  if (mutated === pristine) {
    results.push({ id: mutation.id, verdict: 'NOOP', note: '变异没改动任何字符（正则没匹配上）' });
    writeFileSync(join(workDir, mutation.file), pristine, 'utf8');
    continue;
  }

  writeFileSync(join(workDir, mutation.file), mutated, 'utf8');
  const result = run(workDir);
  results.push({
    id: mutation.id,
    verdict: result.ok ? 'SURVIVED' : 'KILLED',
    note: mutation.note ?? '',
  });
  writeFileSync(join(workDir, mutation.file), pristine, 'utf8');
  console.log(`${result.ok ? 'SURVIVED' : 'KILLED  '} ${mutation.id}${mutation.note ? `  ${mutation.note}` : ''}`);
}

// ---- 汇总 -------------------------------------------------------------------
const killed = results.filter((r) => r.verdict === 'KILLED').length;
const survived = results.filter((r) => r.verdict === 'SURVIVED');
const noop = results.filter((r) => r.verdict === 'NOOP');

console.log(`\n${results.length} 组变异：${killed} KILLED / ${survived.length} SURVIVED / ${noop.length} NOOP`);

if (survived.length > 0) {
  console.error('\n✗ 有变异存活——这些行没有被任何断言区分，是 verification 缺口：');
  for (const item of survived) console.error(`  - ${item.id}${item.note ? `  ${item.note}` : ''}`);
  console.error('  处置：删掉冗余代码，或补一条只有它能过的断言，然后在 review.md 记一条 finding。');
  console.error('  例外：如果这条变异其实**等价**（改了写法但行为一模一样，例如 out += x → out = out + x），');
  console.error('  存活是正常的——把它从清单里删掉，别为它硬补断言（补出来的只会是同义反复）。');
}
if (noop.length > 0) {
  console.error('\n✗ 有变异没改到东西（NOOP），别把它当成 KILLED：');
  for (const item of noop) console.error(`  - ${item.id}  ${item.note}`);
}

if (flags.keep) console.log(`\n副本保留在：${workDir}`);
else rmSync(workDir, { recursive: true, force: true });

process.exit(survived.length === 0 && noop.length === 0 ? 0 : 1);
