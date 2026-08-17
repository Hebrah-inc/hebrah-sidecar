# Contributing to hebrah-sidecar

> **Note:** This repo is **legacy**. New VM work belongs in
> [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates).
> Pull requests here should be limited to bug fixes that keep the legacy
> `HYPERVISOR=microvm-nix` cold-`nix run` flow working on existing developer
> machines.

## Development setup

You need Nix with flakes enabled, and — on macOS — a Linux remote builder
to build the Linux guest.

```bash
git clone https://github.com/Hebrah-inc/hebrah-sidecar.git
cd hebrah-sidecar

# build
nix build .#sidecar-launcher

# run (after exporting HEBRAH_VM_CONFIG_DIR and HEBRAH_HEALTH_HOST_PORT)
nix run .#sidecar-launcher
```

## Layout

```text
.
├── flake.nix                # Outputs: packages.<host>.sidecar-launcher / sidecar-microvm
├── flake.lock
├── README.md
├── LICENSE                  # MIT
├── SECURITY.md              # Private disclosure channel
├── CODE_OF_CONDUCT.md       # Contributor Covenant v2.1
├── .gitignore
├── nix/                     # NixOS module fragments
│   ├── sidecar-module.nix
│   └── clinic-simulator-module.nix
└── packages/                # Python services inside the guest
    ├── hebrah-sidecar-health.{py,nix}
    ├── hebrah-sidecar-hl7.{py,nix}
    ├── hebrah-sidecar-writeback.{py,nix}
    ├── clinic-fhir-server.py
    └── clinic-hl7-server.py
```

## Coding style

- **Nix**: `nixfmt` (or `nixfmt-rfc-style`).
- **Python**: PEP 8 + `pathlib` + `argparse`. Guest services intentionally use
  `BaseHTTPHandler` to keep the rootfs small — don't introduce `flask` /
  `fastapi` without discussion.
- **Shell**: `set -euo pipefail` at the top of every script.

## Adding a guest service

1. Add `packages/<name>.py` and `packages/<name>.nix` (the `.nix` just
   `readFile`s the `.py` so the rootfs is reproducible from a single source).
2. Mount it from the relevant module in `nix/`.
3. If it exposes admin endpoints, gate them on `X-Hebrah-Internal-Secret`
   matching the env-loaded secret.

## Pull request process

1. Fork the repository and create a branch.
2. Run `nix flake check` and `nix build .#sidecar-launcher` before pushing.
3. Keep PRs scoped — one change per PR.
4. Open a PR. CI will run `nix flake check` and `nix build` of the sidecar
   launcher.

## Security disclosures

See [`SECURITY.md`](./SECURITY.md). Please don't file public issues for
security bugs — email security@hebrah.com.

## License

By contributing, you agree that your contributions will be licensed under the
MIT License. See [`LICENSE`](./LICENSE).