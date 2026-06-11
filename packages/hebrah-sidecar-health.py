#!/usr/bin/env python3
"""Sidecar health agent — HTTP :8080 and health.json on shared config dir."""

from __future__ import annotations

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def load_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.is_file():
        return data
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        data[key.strip()] = value.strip()
    return data


def write_health(config_dir: Path, payload: dict) -> None:
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "health.json").write_text(json.dumps(payload, indent=2) + "\n")


class Handler(BaseHTTPRequestHandler):
    payload: dict = {}

    def log_message(self, fmt: str, *args) -> None:
        return

    def do_GET(self) -> None:
        if self.path not in ("/health", "/health/"):
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(self.payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    config_dir = Path(os.environ.get("HEBRAH_CONFIG_DIR", "/hebrah-config"))
    env_file = config_dir / "hebrah.env"
    env = load_env(env_file)
    vm_id = env.get("HEBRAH_VM_ID", os.environ.get("HEBRAH_VM_ID", "unknown"))
    payload = {
        "status": "ok",
        "vm_id": vm_id,
        "stage": "ready",
        "org_id": env.get("HEBRAH_ORG_ID"),
        "connection_id": env.get("HEBRAH_CONNECTION_ID"),
        "environment": env.get("HEBRAH_ENVIRONMENT"),
    }
    write_health(config_dir, payload)
    Handler.payload = payload
    port = int(os.environ.get("HEBRAH_HEALTH_PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    threading.Thread(target=lambda: write_health(config_dir, payload), daemon=True).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
