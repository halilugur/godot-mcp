#!/usr/bin/env python3
"""stdio <-> local HTTP bridge for MCP clients that can only start a command (stdio transport).

It forwards each JSON-RPC line from stdin to the Local MCP server running inside the Godot
editor on this machine (127.0.0.1) and prints the reply. Standard library only; it never
contacts any other host.

Usage:  python3 stdio_bridge.py [--port 9777] [--token TOKEN]
"""
import argparse
import json
import sys
import urllib.error
import urllib.request


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9777)
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    url = "http://127.0.0.1:%d/mcp" % args.port
    # ProxyHandler({}) makes sure a system proxy is never used for this local request.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if args.token:
        headers["Authorization"] = "Bearer " + args.token

    for raw in sys.stdin.buffer:
        line = raw.strip()
        if not line:
            continue
        reply = None
        try:
            request = urllib.request.Request(url, data=line, headers=headers, method="POST")
            with opener.open(request, timeout=60) as response:
                body = response.read()
                if body:
                    reply = body.decode("utf-8")
        except urllib.error.HTTPError as exc:
            body = exc.read()
            if body.strip().startswith(b"{"):
                reply = body.decode("utf-8")
            else:
                reply = _error(line, "Local MCP server answered HTTP %d: %s" % (exc.code, body.decode("utf-8", "replace")))
        except Exception as exc:  # Godot is closed or the plugin is disabled.
            reply = _error(line, "Cannot reach the Godot editor on %s (%s). Open the project in Godot and enable the Local MCP plugin." % (url, exc))
        if reply:
            sys.stdout.write(reply.replace("\n", " ") + "\n")
            sys.stdout.flush()


def _error(line: bytes, message: str):
    try:
        request = json.loads(line)
    except ValueError:
        return json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
    if not isinstance(request, dict) or "id" not in request:
        return None  # Notifications get no reply.
    return json.dumps({"jsonrpc": "2.0", "id": request["id"], "error": {"code": -32000, "message": message}})


if __name__ == "__main__":
    main()
