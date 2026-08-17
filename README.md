# hebrah-sidecar

> ⚠️ **Legacy flake.** New VM work happens in
> [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates)
> — golden erofs bundles, `HYPERVISOR=golden-qemu` on the Mac orchestrator,
> and the active security work. This repo remains as a reference for
> cold `nix run` via `HYPERVISOR=microvm-nix`.

NixOS microVM image for [Hebrah](https://github.com/Hebrah-inc) connection
sidecars. Built with
[microvm.nix](https://github.com/microvm-nix/microvm.nix) for local
development (vfkit on macOS, QEMU on Linux).

## Status

| | |
|---|---|
| Maintenance | Bug fixes only |
| Active dev | [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates) |
| MCP server | [`hebrah-mcp-host`](https://github.com/Hebrah-inc/hebrah-mcp-host) |
| Control plane | [`hebrah-api`](https://github.com/Hebrah-inc/hebrah-api) |

## Flake outputs

| Output | Purpose |
|--------|---------|
| `packages.<host>.sidecar-launcher` | Start a sidecar microVM (orchestrator calls this) |
| `packages.<host>.sidecar-microvm` | microvm.nix declared runner |
| `packages.<host>.clinic-simulator` | Clinic stub microVM runner |
| `packages.<host>.clinic-launcher` | Start clinic simulator |
| `packages.<host>.sidecar-rootfs` | Rootfs artifact (erofs when built on Linux) |
| `packages.<host>.hebrah-sidecar-hl7` | Standalone HL7 v2 guest package |

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- On **macOS**: a **Linux remote builder** to build the NixOS guest. See
  [local-microvm-development.md](https://github.com/Hebrah-inc/hebrah/blob/main/documentation/local-microvm-development.md)
  for the hebrah-specific helper script (`scripts/setup-nix-linux-builder.sh`).

## Build

```bash
cd hebrah-sidecar
nix --extra-experimental-features 'nix-command flakes' build .#sidecar-launcher
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

nix --extra-experimental-features 'nix-command flakes' run .#sidecar-launcher
curl -s "http://127.0.0.1:$HEBRAH_HEALTH_HOST_PORT/health" | jq .
```

## Health contract

Provisioning health uses **9p `health.json` on the host** as the primary
probe (orchestrator reads `vm_dir/health.json` written by the guest). HTTP is
secondary / used for HL7 flight checks.

| Probe | Path | When |
|-------|------|------|
| **Primary** | `$HEBRAH_VM_CONFIG_DIR/health.json` on host (9p virtio share) | Create → health gate |
| **Secondary** | `GET :8080/health` via QEMU hostfwd | Fallback, HL7 probe |

- File payload: `{ "status": "ok", "vm_id": "...", "stage": "ready", ... }`
- HTTP: same JSON at `GET :8080/health`

### microvm.nix integration

Built with [microvm.nix](https://github.com/microvm-nix/microvm.nix): guest
NixOS image, `microvm-run`, Cachix substituter `microvm.cachix.org`.

Runtime config uses `extraArgsScript` (not `microvm.shares`) because
`HEBRAH_VM_CONFIG_DIR` and per-VM host ports are chosen at launch time.
QEMU user netdev + `hostfwd` stay in `extraArgsScript`; 9p export uses
`security_model=mapped-xattr` with `fmode`/`dmode` so guest-created files
appear on the host as the QEMU user (`ubuntu` on EC2). `passthrough` maps
guest root to host root and fails when QEMU is unprivileged.

## Phase 2 sidecar agents

| Port | Service | Purpose |
|------|---------|---------|
| 8080 | health | Provisioning health check |
| 8082 | write-back | `POST /v1/writeback/chart-note`, `/order`, `/task-response` |
| 8083 | HL7 HTTP | `POST /hl7/inject` |
| 2575 | HL7 MLLP | TCP listener with AA ACK |

Host port forwards (QEMU): `HEBRAH_HEALTH_HOST_PORT`, `+1` write-back,
`+2` HL7 HTTP, `+3` MLLP.

Clinic simulator (`clinic-launcher`): `POST /hl7/send/{template_id}` on
`:8081` pushes MLLP to the sidecar WG address. The
`scripts/dev-clinic-sidecar-pair.sh` helper that pairs them lives in the
hebrah umbrella repo (not here).

Orchestrator HL7 flight check: `POST /v1/vms/{vm_id}/hl7-probe`

## Layout

```text
.
├── flake.nix                # Outputs: see table above
├── flake.lock
├── LICENSE
├── README.md
├── SECURITY.md
├── CONTRIBUTING.md
├── .gitignore
├── nix/                    # NixOS module fragments
│   ├── sidecar-module.nix
│   └── clinic-simulator-module.nix
└── packages/               # Python services inside the guest
    ├── clinic-fhir-server.py
    ├── clinic-hl7-server.py
    ├── hebrah-sidecar-health.{py,nix}
    ├── hebrah-sidecar-hl7.{py,nix}
    └── hebrah-sidecar-writeback.{py,nix}
```

## Env injected at VM start

Written by orchestrator to `$HEBRAH_VM_CONFIG_DIR/hebrah.env`:

| Variable | Purpose |
|----------|---------|
| `HEBRAH_VM_ID` | e.g. `fc-sa-{connectionId}` |
| `HEBRAH_ORG_ID` | Organization id |
| `HEBRAH_CONNECTION_ID` | Connection id |
| `HEBRAH_ENVIRONMENT` | `sandbox` or `live` |
| `HEBRAH_API_URL` | Control plane URL for sidecar event ingress |
| `HEBRAH_INTERNAL_SECRET` | Shared secret for `/v1/internal/sidecar/events` |
| `HEBRAH_WG_PRIVATE_KEY` | WireGuard private key (microvm-nix mode) |
| `HEBRAH_WG_LISTEN_PORT` | UDP listen port |

## Security

See [SECURITY.md](./SECURITY.md). For active VM platform work, see
[`hebrah-vm-templates/SECURITY.md`](https://github.com/Hebrah-inc/hebrah-vm-templates/blob/main/SECURITY.md).

## License

MIT — see [LICENSE](./LICENSE).