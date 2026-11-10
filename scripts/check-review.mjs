#!/usr/bin/env node
// review.md 的门禁：把"结论"变成可执行的退出码。
//
// 用法：
//   node scripts/check-review.mjs openspec/changes/<change>/review.md
//
// 退出码：
//   0 = 可以勾 review 收口框 / 可以 archive（✅ 通过 或 ⚠️ 有条件通过，且 high/medium 无 open）
//   1 = 阻塞（⛔ 或开放中的 high/medium）
//   2 = 参数/文件问题、认不出 verdict —— 一律当失败处理，不放行
//
// 为什么需要它：openspec 的 all_done 只数 tasks.md 的复选框，不读 review.md。
// 没有这一步，先勾框再写一份"⛔ 阻塞"的结论，CLI 照样 all_done 并允许 archive。
//
// verdict 行的约定格式（见 review skill 第 6 节）：
//   <通过 / 有条件通过 / 阻塞> — high N / medium N / low N / auto-decided N / rejected N
// 这里的 N 指**仍未处理**的条数；已修复的写进括号，例如 medium 2（均已 fixed）。

import { readFileSync } from 'node:fs';
import process from 'node:process';

const file = process.argv[2];

if (!file) {
  console.error('用法: node scripts/check-review.mjs <review.md>');
  process.exit(2);
}

let text;
try {
  text = readFileSync(file, 'utf8');
} catch {
  console.error(`✗ 读不到 ${file}`);
  process.exit(2);
}

const section = text.match(/^##[ \t]*Verdict[ \t]*$([\s\S]*?)(?=^##[ \t]|(?![\s\S]))/m);
const verdictLine = (section?.[1] ?? '')
  .split(/\r?\n/)
  .map((line) => line.trim())
  .find((line) => line.length > 0 && !line.startsWith('透镜'));

if (!verdictLine) {
  console.error(`✗ ${file} 里找不到 "## Verdict" 下的结论行`);
  process.exit(2);
}

// 状态词只认破折号之前那段，避免把"不阻塞 archive"这类叙述当成阻塞结论
const status = verdictLine.split(/[—–]/)[0].trim();

if (/⛔|阻塞/.test(status)) {
  console.error(`✗ review 结论是阻塞：${verdictLine}`);
  process.exit(1);
}

if (!/✅|⚠|通过/.test(status)) {
  console.error(`✗ 认不出 verdict（要 ✅ 通过 / ⚠️ 有条件通过 / ⛔ 阻塞）：${verdictLine}`);
  process.exit(2);
}

// 只看结论行前半段（分号之前）的计数，避开"本轮修复 medium 5"这类叙述
const counts = verdictLine.split(/[；;]/)[0];

const openRe = /(high|medium)\s*(\d+)([^/|]*)/gi;
const open = [];
let m;
while ((m = openRe.exec(counts)) !== null) {
  const n = Number(m[2]);
  const tail = m[3] ?? '';
  const exempt = /已|fixed|修复|关闭|resolved/i.test(tail);
  if (n > 0 && !exempt) open.push(`${m[1]} ${n}${tail.trim()}`);
}

if (open.length > 0) {
  console.error(`✗ 还有未处理的 high/medium，先修完再收口：${open.join('；')}`);
  process.exit(1);
}

console.log(`✓ review 可收口：${verdictLine}`);
process.exit(0);
