#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const pkgPath = path.join(process.cwd(), 'package.json');

try {
  const text = fs.readFileSync(pkgPath, 'utf8');

  // 1) Detect common merge conflict markers
  const conflictRe = /(^|\n)\s*(<{7}|>{7}|={7})/;
  if (conflictRe.test(text)) {
    console.error('Error: Merge conflict markers found in package.json (<<<<<<<, =======, >>>>>>>). Please resolve them.');
    process.exit(2);
  }

  // 2) Detect duplicate top-level keys (common when merging JSON fragments)
  let i = 0;
  const len = text.length;
  let depth = 0;
  const seen = new Set();
  const duplicates = [];

  while (i < len) {
    const ch = text[i];
    if (ch === '{') { depth++; i++; continue; }
    if (ch === '}') { depth--; i++; continue; }

    if (depth === 1) {
      const m = text.slice(i).match(/^\s*"([^"\\]+)"\s*:/);
      if (m) {
        const key = m[1];
        if (seen.has(key) && !duplicates.includes(key)) duplicates.push(key);
        seen.add(key);
        i += m[0].length;
        continue;
      }
    }
    i++;
  }

  if (duplicates.length) {
    console.error('Error: Duplicate top-level keys in package.json detected:', duplicates.join(', '));
    process.exit(2);
  }

  // 3) Ensure valid JSON
  try {
    JSON.parse(text);
  } catch (e) {
    console.error('Error: package.json is not valid JSON:', e.message);
    process.exit(2);
  }

  console.log('OK: package.json is valid and has no merge markers or duplicate top-level keys.');
  process.exit(0);
} catch (err) {
  console.error('Error reading or validating package.json:', err.message);
  process.exit(2);
}

// CI trigger: touch to force workflow run
