# hebrah-sidecar

NixOS microVM image for hebrah connection sidecars. Built with [microvm.nix](https://microvm.nix.github.io/microvm.nix/) for local development (vfkit on macOS, QEMU on Linux) and designed for future AWS Firecracker deployment.

## Flake outputs

| Output | Purpose |
|--------|---------|
| `packages.<host>.sidecar-launcher` | Start a sidecar microVM (orchestrator calls this) |
| `packages.<host>.sidecar-microvm` | microvm.nix declared runner |
| `packages.<host>.clinic-simulator` | Clinic stub microVM runner |
| `packages.<host>.clinic-launcher` | Start clinic simulator |
| `packages.<host>.sidecar-rootfs` | Rootfs artifact (AWS-ready; erofs when built on Linux) |

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- On **macOS**: a **Linux remote builder** to build the NixOS guest (see [documentation/local-microvm-development.md](../documentation/local-microvm-development.md))

## Build

```bash
cd hebrah-sidecar
nix build .#sidecar-launcher
```

## Run manually (orchestrator normally does this)

```bash
export HEBRAH_VM_CONFIG_DIR="$HOME/.hebrah/microvms/demo/hebrah.env.d"
export HEBRAH_HEALTH_HOST_PORT=18080
export HEBRAH_VM_PIDFILE="$HEBRAH_VM_CONFIG_DIR/pid"
mkdir -p "$HEBRAH_VM_CONFIG_DIR"
cat >"$HEBRAH_VM_CONFIG_DIR/hebrah.env" <<EOF
HEBRAH_VM_ID=fc-sa-demo
HEBRAH_ORG_ID=org_demo
HEBRAH_CONNECTION_ID=conn_demo
HEBRAH_ENVIRONMENT=sandbox
EOF

nix run .#sidecar-launcher
curl -s "http://127.0.0.1:$HEBRAH_HEALTH_HOST_PORT/health" | jq .
```

## Health contract

- HTTP: `GET :8080/health` → `{ "status": "ok", "vm_id": "...", "stage": "ready" }`
- File (shared virtiofs dir): `health.json` with the same payload (used when host port-forward is unavailable)

## AWS-ready artifacts (not deployed yet)

```bash
nix build .#sidecar-rootfs
```

Future production: upload rootfs to `s3://hebrah-artifacts/sidecar/{version}/rootfs.erofs` and pin `SIDECAR_ROOTFS_VERSION` on orchestrator hosts.

## Env injected at VM start

Written by orchestrator to `$HEBRAH_VM_CONFIG_DIR/hebrah.env`:

| Variable | Purpose |
|----------|---------|
| `HEBRAH_VM_ID` | e.g. `fc-sa-{connectionId}` |
| `HEBRAH_ORG_ID` | Organization id |
| `HEBRAH_CONNECTION_ID` | Connection id |
| `HEBRAH_ENVIRONMENT` | `sandbox` or `live` |
| `HEBRAH_WG_PRIVATE_KEY` | WireGuard private key (microvm-nix mode) |
| `HEBRAH_WG_LISTEN_PORT` | UDP listen port |
