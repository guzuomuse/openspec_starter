#!/usr/bin/env node
// review.md 的门禁：把"结论"变成可执行的退出码。
//
// 用法：
//   node scripts/check-review.mjs openspec/changes/<change>/review.md
//
// 退出码：
//   0 = 可以勾 review 收口框 / 可以 archive
//   1 = 阻塞（⛔、有 open 的 high/medium、或 Verdict 与 Findings 对不上）
//   2 = 参数/文件问题、认不出 verdict 或结构 —— 一律当失败处理，不放行
//
// 为什么需要它：openspec 的 all_done 只数 tasks.md 的复选框，不读 review.md。
//
// 设计要点（v2）：**不信叙述，只信结构**。
//   v1 会在 Verdict 行的括号里找"已 fixed"来豁免计数，结果一句
//   `medium 2（已降级为 low，留待后续）` 就能放行——判据又落回了措辞。
//   现在改为：
//     1. Verdict 的 high/medium 计数必须是 0（括号内容一律不参与豁免）；
//     2. 再从 Findings 块反推 open 的 high/medium（块里 `- 状态：` 不以
//        fixed/rejected/closed 开头即算 open）；
//     3. 两边对不上（Verdict 报的比反推的少）= 不可信，直接阻塞。
//   想蒙过去得同时改两处结构化字段，而不是换一种说法。
//
// v5（与 schema v5 同步）再加两条结构检查，专治"写了承诺但没兑现"：
//     4. `## 验证记录` 只允许一节（重复 = 两份互相矛盾的记录）；
//     5. tasks.md 里每处 `[RED→绿]` 必须在验证记录里对应一行红证。
//        review 里写一句"按约定应补红证"不算做了——欠条必须真还。
//
// 副本会落后：每个消费者仓库自带一份，老副本少了新检查，跑出来的 0 是旧判据的 0。
// 所以成功行打印判据版本（gate v5）——版本对不上就是跑错了脚本（多半是跑错了目录）。
//
// v5.1 修一处误判：欠条原先按整文件子串 `[RED→绿` 计数，散文里提到这套机制（例如
// 「本切片是真红，红灯异常处理不适用」）也会被算成一笔债，于是唯一的通关办法是改措辞——
// 门禁逼人撒谎。现在只数**任务行**（复选框行）上的标注，并在阻塞时把被判为欠条的行原样列出来。

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import process from 'node:process';

const GATE_VERSION = 'v8';

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

const fail = (msg) => {
  console.error(`✗ ${msg}`);
  process.exit(1);
};
const broken = (msg) => {
  console.error(`✗ ${msg}`);
  process.exit(2);
};

// ---- 1. Verdict -------------------------------------------------------------
const verdictSection = text.match(/^##[ \t]*Verdict[ \t]*$([\s\S]*?)(?=^##[ \t]|(?![\s\S]))/m);
const verdictLine = (verdictSection?.[1] ?? '')
  .split(/\r?\n/)
  .map((line) => line.trim())
  .find((line) => line.length > 0 && !line.startsWith('透镜'));

if (!verdictLine) broken(`${file} 里找不到 "## Verdict" 下的结论行`);

// 状态词只认破折号之前那段，避免把"不阻塞 archive"当成阻塞结论
const status = verdictLine.split(/[—–]/)[0].trim();

if (/⛔|阻塞/.test(status)) fail(`review 结论是阻塞：${verdictLine}`);
if (!/✅|⚠|通过/.test(status)) {
  broken(`认不出 verdict（要 ✅ 通过 / ⚠️ 有条件通过 / ⛔ 阻塞）：${verdictLine}`);
}

// 计数只看分号之前，且不做任何"已修"豁免
const counts = verdictLine.split(/[；;]/)[0];
const claimed = {};
for (const level of ['high', 'medium']) {
  const hit = counts.match(new RegExp(`${level}\\s*(\\d+)`, 'i'));
  if (!hit) broken(`Verdict 行缺 ${level} 计数（约定格式：high N / medium N / low N）：${verdictLine}`);
  claimed[level] = Number(hit[1]);
}

// ---- 2. Findings 反推 -------------------------------------------------------
const findingsSection = text.match(/^##[ \t]*Findings[ \t]*$([\s\S]*?)(?=^##[ \t]|(?![\s\S]))/m);
const blocks = (findingsSection?.[1] ?? '')
  .split(/^###[ \t]+/m)
  .slice(1)
  .map((raw) => {
    const head = raw.split(/\r?\n/, 1)[0];
    const severity = (head.match(/\[(\w+)\]/)?.[1] ?? '').toLowerCase();
    const statusLine = raw.match(/^[ \t]*[-*][ \t]*\*{0,2}状态\*{0,2}[ \t]*[：:][ \t]*(.*)$/m);
    return {
      title: head.trim().slice(0, 60),
      severity,
      status: statusLine ? statusLine[1].trim() : null,
    };
  });

const isClosed = (value) => /^(fixed|rejected|closed|已修|已拒|已关闭)/i.test(value ?? '');
const derived = { high: 0, medium: 0 };
const openList = [];

for (const block of blocks) {
  if (!['high', 'medium'].includes(block.severity)) continue;
  if (isClosed(block.status)) continue;
  derived[block.severity] += 1;
  openList.push(`${block.severity}「${block.title}」${block.status === null ? '（缺 - 状态：）' : ''}`);
}

if (openList.length > 0) fail(`还有未处理的 high/medium：\n  - ${openList.join('\n  - ')}`);

// ---- 3. 一致性 --------------------------------------------------------------
for (const level of ['high', 'medium']) {
  if (claimed[level] !== derived[level]) {
    fail(
      `Verdict 与 Findings 对不上：Verdict 报 ${level} ${claimed[level]}，` +
        `Findings 反推 ${level} ${derived[level]}。以 Findings 为准，先把结论改成实际状态。`,
    );
  }
}

// ---- 4. 结构检查：验证记录唯一 + [RED→绿] 欠条还清 --------------------------
const verificationSections = [
  ...text.matchAll(/^##[ \t]*验证记录[ \t]*$([\s\S]*?)(?=^##[ \t]|(?![\s\S]))/gm),
];

if (verificationSections.length > 1) {
  broken(
    `「## 验证记录」写了 ${verificationSections.length} 节，只允许一节` +
      `（重复通常是两份互相矛盾的记录：一份说固定点是基线，一份说工作区）`,
  );
}

const verificationText = verificationSections.map((m) => m[1]).join('\n');
const redProofLines = verificationText
  .split(/\r?\n/)
  .filter((line) => line.includes('红证')).length;

const tasksPath = join(dirname(file), 'tasks.md');
let debtLines = [];
try {
  debtLines = readFileSync(tasksPath, 'utf8')
    .split(/\r?\n/)
    .map((line, index) => ({ line, no: index + 1 }))
    // 只数「任务行上的标注」：必须是一个复选框任务，且带 [RED→绿。
    // 散文里提到这套机制（例如解释「本切片是真红，红灯异常处理不适用」）不算欠条——
    // 按整文件子串计数会把解释性文字也算成债，逼着人改措辞来绕门禁，那才是真的漏洞。
    .filter(({ line }) => /^\s*[-*]\s*\[[^\]]{0,4}\]/.test(line) && line.includes('[RED→绿'));
} catch {
  debtLines = []; // 没有 tasks.md 就不查这条
}

if (debtLines.length > redProofLines) {
  const listed = debtLines.map(({ line, no }) => `    tasks.md:${no}  ${line.trim()}`).join('\n');
  fail(
    `tasks.md 有 ${debtLines.length} 处任务行上的 [RED→绿] 标注，验证记录里只有 ${redProofLines} 行红证。\n` +
      `  被判为欠条的行（散文提及不计）：\n${listed}\n` +
      `  每处标注都是一张欠条：删掉被钉的实现 → 对应断言必须变红 → 恢复，\n` +
      `  并在验证记录写一行「- 红证 [<任务号>]：删了什么 → 哪条断言变红」。\n` +
      `  删了也不红 = 断言没有区分力，记一条 medium / verification finding。`,
  );
}

console.log(`✓ review 可收口（gate ${GATE_VERSION}）：${verdictLine}`);
process.exit(0);
