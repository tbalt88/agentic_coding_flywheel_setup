# CASS Session Data Format Research

Research completed: 2025-12-21
Bead: eli

## Overview

CASS (Coding Agent Session Search) is a unified TUI/CLI search tool for coding agent histories. It provides full-text search and export capabilities across multiple agent session formats.

## Supported Agents (Connectors)

From `cass capabilities`:
- `codex` - OpenAI Codex CLI
- `claude_code` - Claude Code
- `gemini` - Gemini CLI
- `opencode` - OpenCode
- `amp` - Amp
- `cline` - Cline
- `aider` - Aider
- `cursor` - Cursor
- `chatgpt` - ChatGPT
- `pi_agent` - Pi Agent

## CLI Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `cass tui` | Launch interactive TUI |
| `cass search "<query>"` | Full-text search |
| `cass export <path>` | Export conversation to markdown/json/html |
| `cass stats` | Show statistics about indexed data |
| `cass index` | Run indexer |

### Discovery/Context Commands

| Command | Description |
|---------|-------------|
| `cass view <path> -n <line>` | View source file at specific line |
| `cass expand <path> -n <line>` | Show messages around a line |
| `cass context <path>` | Find related sessions |
| `cass timeline` | Show activity timeline |

### Introspection Commands

| Command | Description |
|---------|-------------|
| `cass capabilities` | Discover features, versions, limits |
| `cass introspect` | Full API schema introspection |
| `cass status` / `cass state` | Quick health check |
| `cass health` | Minimal health check (<50ms) |
| `cass diag` | Diagnostic information |

## Session File Format

Sessions are stored as JSONL files. Each line is a JSON object with:

```json
{
  "payload": { ... },
  "timestamp": "2025-12-05T07:14:00.756Z",
  "type": "<event_type>"
}
```

### Event Types (Codex CLI format)

**Note:** Event type schemas vary by agent. The examples below are from Codex CLI sessions.

1. **`response_item`** - Initial session metadata
   ```json
   {
     "payload": {
       "cli_version": "0.65.0",
       "cwd": "/path/to/workspace",
       "git": {
         "branch": "main",
         "commit_hash": "abc123",
         "repository_url": "https://..."
       },
       "id": "uuid",
       "instructions": "AGENTS.md content..."
     }
   }
   ```

2. **`event_msg`** - User messages
   ```json
   {
     "payload": {
       "images": [],
       "message": "User prompt text",
       "type": "user_message"
     }
   }
   ```

3. **`turn_context`** - Turn configuration
   ```json
   {
     "payload": {
       "approval_policy": "never",
       "cwd": "/path/to/workspace",
       "effort": "high",
       "model": "gpt-5.2-codex",
       "sandbox_policy": {"type": "danger-full-access"},
       "summary": "auto"
     }
   }
   ```

## Search API

### Basic Search
```bash
cass search "query" --json --limit 10
```

### Search Response Schema
```json
{
  "count": 3,
  "cursor": null,
  "hits": [
    {
      "agent": "codex",
      "content": "matched text...",
      "created_at": 1764983273293,
      "line_number": 1163,
      "match_type": "exact",
      "score": 1.0,
      "snippet": "",
      "source_path": "/path/to/session.jsonl",
      "title": "Session title",
      "workspace": "/path/to/workspace"
    }
  ],
  "hits_clamped": false,
  "limit": 10,
  "max_tokens": null,
  "offset": 0,
  "query": "query",
  "request_id": null,
  "total_matches": 3
}
```

### Search Features
- FTS5 syntax: phrases (`"build plan"`), prefix (`migrat*`), boolean (`plan AND users`)
- Filter by agent: `--agent claude_code`
- Filter by workspace: `--workspace /path`
- Pagination: `--offset N --limit M`
- Field selection: `--fields source_path,line_number,agent`

## Export Formats

```bash
cass export <session_path> --format <format>
```

| Format | Description |
|--------|-------------|
| `markdown` | Markdown with headers (default) |
| `text` | Plain text |
| `json` | JSON array of messages |
| `html` | HTML with styling |

Option `--include-tools` adds tool use details.

## Statistics

```bash
cass stats --json
```

Returns:
```json
{
  "by_agent": {
    "claude_code": {"conversations": 100, "messages": 5000},
    "codex": {"conversations": 50, "messages": 2500}
  },
  "total": {
    "conversations": 594,
    "messages": 87625
  }
}
```

## Capabilities

From `cass capabilities --json`:

- **API Version**: 1
- **Contract Version**: "1"
- **Max Limit**: 10000 results
- **Max Fields**: 50
- **Max Aggregation Buckets**: 10

### Features
- `json_output`, `jsonl_output`
- `time_filters`, `field_selection`
- `cursor_pagination`
- `wildcard_fallback`
- `highlight_matches`
- `query_explain`
- `dry_run`

## Session Storage Locations

Paths observed during research (may vary by platform/version):

| Agent | Path Pattern | Verified |
|-------|--------------|----------|
| Codex | `~/.codex/sessions/YYYY/MM/rollout-*.jsonl` | Yes |
| Amp | `~/Library/Application Support/amp/amp/thread-*.json` | Yes |
| Claude Code | Platform-specific (use `cass diag` to discover) | No |
| Gemini | Platform-specific (use `cass diag` to discover) | No |

**Note:** Use `cass diag --json` to discover actual session paths on your system.

## Limitations and Gaps

1. **No `list` command** - Must use `search "*"` or `timeline` to discover sessions
2. **No session metadata API** - Can't get session count/dates without exporting
3. **Timeline command may have issues** - DB schema errors observed in v0.1.35 (`no such column: c.agent`)
4. **Read-only** - Cannot modify or delete session data via CASS
5. **No session filtering by date** in search (only in timeline)
6. **Large sessions can be slow** to export (10K+ messages)
7. **No streaming export** - Must wait for full export to complete

## Integration Recommendations

1. **For session discovery**: Use `cass search "*" --limit 100 --fields source_path,title,agent`
2. **For context lookup**: Use `cass context <path>` to find related sessions
3. **For follow-up on search hits**: Use `cass view <path> -n <line>` or `cass expand`
4. **For health checks**: Use `cass health` (fast, <50ms)
5. **For full introspection**: Use `cass introspect --json`

## Example Workflow

```bash
# 1. Find sessions mentioning a topic
cass search "authentication" --json --limit 20

# 2. Get context around a hit
cass expand /path/to/session.jsonl -n 1163 --context 5

# 3. Export full session for review
cass export /path/to/session.jsonl --format markdown -o session.md

# 4. Check index freshness
cass status --json
```
