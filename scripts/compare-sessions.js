#!/usr/bin/env node
/**
 * Compare two telemetry session summaries (A/B test).
 *
 * Usage:
 *   node compare-sessions.js <summary-A.json> <summary-B.json>
 *
 * Convention: A = WITH plugin, B = WITHOUT plugin.
 * If has_index flags differ, the script auto-detects which is which.
 */

const fs = require('fs');
const path = require('path');

if (process.argv.length < 4) {
  console.error('Usage: node compare-sessions.js <summary-A.json> <summary-B.json>');
  process.exit(1);
}

const fileA = process.argv[2];
const fileB = process.argv[3];

let a, b;
try { a = JSON.parse(fs.readFileSync(fileA, 'utf8')); } catch (e) { console.error(`Failed to read ${fileA}: ${e.message}`); process.exit(1); }
try { b = JSON.parse(fs.readFileSync(fileB, 'utf8')); } catch (e) { console.error(`Failed to read ${fileB}: ${e.message}`); process.exit(1); }

// Auto-detect: if one has_index and the other doesn't, swap so A=WITH, B=WITHOUT
if (!a.has_index && b.has_index) {
  [a, b] = [b, a];
  console.log('(Auto-swapped: detected A=WITH plugin, B=WITHOUT plugin)\n');
} else if (a.has_index && !b.has_index) {
  console.log('(Confirmed: A=WITH plugin, B=WITHOUT plugin)\n');
} else {
  console.log(`(Warning: both sessions have has_index=${a.has_index} — comparison may be less meaningful)\n`);
}

function delta(valA, valB) {
  if (valB === 0 || valB === null || valB === undefined) return 'N/A';
  const pct = ((valA - valB) / valB) * 100;
  const sign = pct >= 0 ? '+' : '';
  return `${sign}${pct.toFixed(1)}%`;
}

function deltaAbs(valA, valB) {
  const diff = valA - valB;
  const sign = diff >= 0 ? '+' : '';
  return `${sign}${diff}`;
}

function deltaPts(valA, valB) {
  const diff = (valA - valB) * 100;
  const sign = diff >= 0 ? '+' : '';
  return `${sign}${diff.toFixed(1)} pts`;
}

function fmt(n) {
  if (n === null || n === undefined) return 'N/A';
  return typeof n === 'number' ? n.toLocaleString() : String(n);
}

function fmtRatio(n) {
  if (n === null || n === undefined) return 'N/A';
  return `${(n * 100).toFixed(1)}%`;
}

// Gather all unique tool names
const allTools = new Set([
  ...Object.keys(a.tool_calls || {}),
  ...Object.keys(b.tool_calls || {}),
]);

const searchNavTools = ['Read', 'Glob', 'Grep', 'Explore', 'Task'];

// Build table rows
const rows = [
  ['Input Tokens',      fmt(a.tokens?.input),          fmt(b.tokens?.input),          delta(a.tokens?.input || 0, b.tokens?.input || 0)],
  ['Output Tokens',     fmt(a.tokens?.output),         fmt(b.tokens?.output),         delta(a.tokens?.output || 0, b.tokens?.output || 0)],
  ['Cache Creation',    fmt(a.tokens?.cache_creation),  fmt(b.tokens?.cache_creation),  delta(a.tokens?.cache_creation || 0, b.tokens?.cache_creation || 0)],
  ['Cache Read Tokens', fmt(a.tokens?.cache_read),      fmt(b.tokens?.cache_read),      delta(a.tokens?.cache_read || 0, b.tokens?.cache_read || 0)],
  ['Cache Hit Ratio',   fmtRatio(a.tokens?.cache_hit_ratio), fmtRatio(b.tokens?.cache_hit_ratio), deltaPts(a.tokens?.cache_hit_ratio || 0, b.tokens?.cache_hit_ratio || 0)],
  ['API Calls',         fmt(a.api_calls),              fmt(b.api_calls),              deltaAbs(a.api_calls || 0, b.api_calls || 0)],
  ['---', '---', '---', '---'],
];

// Individual tool rows
for (const tool of [...allTools].sort()) {
  const va = (a.tool_calls || {})[tool] || 0;
  const vb = (b.tool_calls || {})[tool] || 0;
  rows.push([`${tool} calls`, fmt(va), fmt(vb), deltaAbs(va, vb)]);
}

rows.push(['---', '---', '---', '---']);
rows.push(['Search/Nav Total', fmt(a.search_nav_total || 0), fmt(b.search_nav_total || 0), delta(a.search_nav_total || 0, b.search_nav_total || 0)]);
rows.push(['Duration (s)',     fmt(a.duration_sec),          fmt(b.duration_sec),          delta(a.duration_sec || 0, b.duration_sec || 0)]);
rows.push(['Compaction Events', fmt(a.compaction_events || 0), fmt(b.compaction_events || 0), deltaAbs(a.compaction_events || 0, b.compaction_events || 0)]);

// Print table
const headers = ['Metric', 'WITH Plugin', 'WITHOUT Plugin', 'Delta'];
const colWidths = headers.map((h, i) => Math.max(h.length, ...rows.filter(r => r[0] !== '---').map(r => String(r[i]).length)));

function padRow(row) {
  return '| ' + row.map((cell, i) => {
    if (cell === '---') return '-'.repeat(colWidths[i]);
    return String(cell).padEnd(colWidths[i]);
  }).join(' | ') + ' |';
}

console.log(padRow(headers));
console.log('|' + colWidths.map(w => '-'.repeat(w + 2)).join('|') + '|');
for (const row of rows) {
  if (row[0] === '---') {
    console.log('|' + colWidths.map(w => '-'.repeat(w + 2)).join('|') + '|');
  } else {
    console.log(padRow(row));
  }
}

// Summary
console.log('\n--- Summary ---');
console.log(`Session A (WITH):    ${a.session_id} | model: ${a.model} | cwd: ${a.cwd}`);
console.log(`Session B (WITHOUT): ${b.session_id} | model: ${b.model} | cwd: ${b.cwd}`);

const inputSaved = a.tokens?.input && b.tokens?.input
  ? b.tokens.input - a.tokens.input
  : null;
if (inputSaved !== null && inputSaved > 0) {
  console.log(`\nPlugin saved ~${inputSaved.toLocaleString()} input tokens (${((inputSaved / b.tokens.input) * 100).toFixed(1)}% reduction)`);
} else if (inputSaved !== null && inputSaved < 0) {
  console.log(`\nPlugin used ~${Math.abs(inputSaved).toLocaleString()} MORE input tokens (${((Math.abs(inputSaved) / b.tokens.input) * 100).toFixed(1)}% increase)`);
}

// Write JSON output alongside
const outputPath = path.join(path.dirname(fileA), 'comparison.json');
const comparison = {
  session_a: a.session_id,
  session_b: b.session_id,
  a_has_index: a.has_index,
  b_has_index: b.has_index,
  deltas: {
    input_tokens_pct: a.tokens?.input && b.tokens?.input ? ((a.tokens.input - b.tokens.input) / b.tokens.input * 100) : null,
    output_tokens_pct: a.tokens?.output && b.tokens?.output ? ((a.tokens.output - b.tokens.output) / b.tokens.output * 100) : null,
    cache_read_pct: a.tokens?.cache_read && b.tokens?.cache_read ? ((a.tokens.cache_read - b.tokens.cache_read) / b.tokens.cache_read * 100) : null,
    api_calls_diff: (a.api_calls || 0) - (b.api_calls || 0),
    search_nav_pct: a.search_nav_total && b.search_nav_total ? ((a.search_nav_total - b.search_nav_total) / b.search_nav_total * 100) : null,
    duration_pct: a.duration_sec && b.duration_sec ? ((a.duration_sec - b.duration_sec) / b.duration_sec * 100) : null,
  },
  generated_at: new Date().toISOString(),
};

try {
  fs.writeFileSync(outputPath, JSON.stringify(comparison, null, 2));
  console.log(`\nComparison JSON written to: ${outputPath}`);
} catch (e) {
  console.error(`Could not write comparison JSON: ${e.message}`);
}
