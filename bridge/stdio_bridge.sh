#!/bin/sh
# Minimal dependency-free stdio-to-HTTP bridge for Local MCP (uses POSIX sh + curl).
# No Python or Node.js required.

URL="${LOCAL_MCP_URL:-http://127.0.0.1:9777/mcp}"
TOKEN="${LOCAL_MCP_TOKEN:-}"

while IFS= read -r line; do
	[ -z "$line" ] && continue
	if [ -n "$TOKEN" ]; then
		resp=$(curl -sS -X POST "$URL" \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer $TOKEN" \
			--data-binary "$line" 2>/dev/null)
	else
		resp=$(curl -sS -X POST "$URL" \
			-H "Content-Type: application/json" \
			--data-binary "$line" 2>/dev/null)
	fi
	rc=$?
	if [ $rc -ne 0 ]; then
		printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32000,"message":"Local MCP unreachable at %s (is Godot open with Local MCP enabled?)"}}\n' "$URL"
	elif [ -n "$resp" ]; then
		printf '%s\n' "$resp"
	fi
done
