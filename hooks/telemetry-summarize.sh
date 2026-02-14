#!/bin/bash
INPUT=$(cat)

# Use node instead of jq for JSON parsing (cross-platform)
eval "$(node -e "
const d = JSON.parse(process.argv[1]);
console.log('SESSION_ID=' + JSON.stringify(d.session_id || ''));
console.log('TRANSCRIPT=' + JSON.stringify(d.transcript_path || ''));
" "$INPUT")"

TELEMETRY_DIR="$HOME/.macromanatlas/telemetry"
mkdir -p "$TELEMETRY_DIR" 2>/dev/null

META_FILE="$TELEMETRY_DIR/${SESSION_ID}.meta.json"
TOOLS_FILE="$TELEMETRY_DIR/${SESSION_ID}.tools.jsonl"
SUMMARY_FILE="$TELEMETRY_DIR/${SESSION_ID}.summary.json"

# If no transcript path provided, try standard location
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  TRANSCRIPT=$(find "$HOME/.claude/projects" -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1)
fi

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "{\"error\":\"transcript not found\",\"session_id\":\"$SESSION_ID\"}" > "$SUMMARY_FILE"
  exit 0
fi

# Use node to parse the transcript JSONL and produce summary
node -e "
const fs = require('fs');
const path = require('path');

const sessionId = process.argv[1];
const transcriptPath = process.argv[2];
const metaPath = process.argv[3];
const toolsPath = process.argv[4];
const summaryPath = process.argv[5];

// Read transcript JSONL
const lines = fs.readFileSync(transcriptPath, 'utf8').split('\n').filter(l => l.trim());

// Track per-requestId data
const requestMap = new Map();
const toolCounts = {};
let compactionEvents = 0;

for (const line of lines) {
  let entry;
  try { entry = JSON.parse(line); } catch { continue; }

  if (entry.type === 'assistant' && entry.message) {
    const reqId = entry.requestId || entry.request_id || 'unknown';
    const usage = entry.message.usage;

    if (usage) {
      if (!requestMap.has(reqId)) {
        // First chunk for this requestId - take input/cache tokens
        requestMap.set(reqId, {
          input_tokens: usage.input_tokens || 0,
          output_tokens: 0,
          cache_creation_input_tokens: usage.cache_creation_input_tokens || 0,
          cache_read_input_tokens: usage.cache_read_input_tokens || 0,
        });
      }
      // Sum output_tokens across chunks
      requestMap.get(reqId).output_tokens += (usage.output_tokens || 0);
    }

    // Count tool_use in content
    if (entry.message.content && Array.isArray(entry.message.content)) {
      for (const block of entry.message.content) {
        if (block.type === 'tool_use') {
          const name = block.name || 'unknown';
          toolCounts[name] = (toolCounts[name] || 0) + 1;
        }
      }
    }
  }

  // Detect compaction events
  if (entry.type === 'system' && entry.message && typeof entry.message === 'string' &&
      entry.message.toLowerCase().includes('compact')) {
    compactionEvents++;
  }
}

// Aggregate totals
let totalInput = 0, totalOutput = 0, totalCacheCreation = 0, totalCacheRead = 0;
for (const [, data] of requestMap) {
  totalInput += data.input_tokens;
  totalOutput += data.output_tokens;
  totalCacheCreation += data.cache_creation_input_tokens;
  totalCacheRead += data.cache_read_input_tokens;
}

const apiCalls = requestMap.size;
const totalCacheTokens = totalCacheCreation + totalCacheRead;
const cacheHitRatio = totalCacheTokens > 0 ? totalCacheRead / totalCacheTokens : 0;

// Read meta for timing
let meta = {};
try { meta = JSON.parse(fs.readFileSync(metaPath, 'utf8')); } catch {}

const startTime = meta.start ? new Date(meta.start) : null;
const endTime = new Date();
const durationSec = startTime ? Math.round((endTime - startTime) / 1000) : null;

// Read tool call log for verification
let toolLogCounts = {};
try {
  const toolLines = fs.readFileSync(toolsPath, 'utf8').split('\n').filter(l => l.trim());
  for (const tl of toolLines) {
    try {
      const t = JSON.parse(tl);
      toolLogCounts[t.tool] = (toolLogCounts[t.tool] || 0) + 1;
    } catch {}
  }
} catch {}

// Search/nav tools
const searchNavTools = ['Read', 'Glob', 'Grep', 'Explore', 'Task'];
const searchNavTotal = searchNavTools.reduce((sum, t) => sum + (toolCounts[t] || 0), 0);

const summary = {
  session_id: sessionId,
  has_index: meta.has_index || false,
  model: meta.model || 'unknown',
  cwd: meta.cwd || 'unknown',
  duration_sec: durationSec,
  api_calls: apiCalls,
  tokens: {
    input: totalInput,
    output: totalOutput,
    cache_creation: totalCacheCreation,
    cache_read: totalCacheRead,
    cache_hit_ratio: Math.round(cacheHitRatio * 10000) / 10000,
  },
  tool_calls: toolCounts,
  tool_calls_from_log: toolLogCounts,
  search_nav_total: searchNavTotal,
  compaction_events: compactionEvents,
  generated_at: new Date().toISOString(),
};

fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
console.log('Telemetry summary written to ' + summaryPath);
" "$SESSION_ID" "$TRANSCRIPT" "$META_FILE" "$TOOLS_FILE" "$SUMMARY_FILE"

exit 0
