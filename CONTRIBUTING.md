# Contributing to hebrah-sidecar

> **This repo is legacy.** New VM work happens in
> [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates),
> which carries the active golden-image workflow. This flake remains as a
> reference for `HYPERVISOR=microvm-nix` cold launches and as a
> historical record.

## Repo scope

This repo ships the legacy NixOS microVM template + launcher used by the
hebrah orchestrator's `microvm-nix` backend.

| Path | Purpose |
|------|---------|
| `flake.nix` | Flake outputs — `packages.<host>.{sidecar-launcher,sidecar-microvm,clinic-launcher,clinic-simulator,sidecar-rootfs,hebrah-sidecar-hl7}`, dev shells, `nixosConfigurations.{sidecar,clinic-simulator}`. |
| `nix/` | NixOS module fragments (`sidecar-module.nix`, `clinic-simulator-module.nix`). |
| `packages/` | Python services that ship inside the guest (health, HL7 v2, write-back, FHIR clinic stubs). |

It is **not** the control plane (see [`hebrah-api`](https://github.com/Hebrah-inc/hebrah-api))
and it is **not** the active golden-image template set (see
[`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates)).

## Development setup

You need Nix with flakes enabled:

```bash
nix --extra-experimental-features 'nix-command flakes' build .#packages.x8664-linux.sidecar-launcher
```

If you're on macOS you'll want a Linux remote builder for the `*linux` outputs:

```bash
# See https://github.com/nix-darwin/nix-darwin or Lima + nix-docker
# The hebrah monorepo ships a helper:
#   bash scripts/setup-nix-linux-builder.sh   (umbrella repo only)
```

For local smoke testing of the orchestrator sidecar path, see the umbrella docs:

- [vm-platform-architecture.md](https://github.com/Hebrah-inc/hebrah/blob/main/documentation/vm-platform-architecture.md)
- [local-microvm-development.md](https://github.com/Hebrah-inc/hebrah/blob/main/documentation/local-microvm-development.md)

External contributors who don't have the umbrella repo can still:

1. `nix flake show` to see all outputs.
2. `nix build .#packages.<host>.sidecar-launcher` to build the launcher.
3. `nix develop` for an interactive shell with `nix`, `nixfmt-classic`, `jq`,
   `curl`, `wireguard-tools` on `$PATH`.

## Code style

- **Nix**: `nixfmt` (the formatter is in the dev shell).
- **Python**: PEP 8 + `pathlib` + `argparse`. The guest services use
  `BaseHTTPHandler` deliberately to keep the rootfs small; please don't
  introduce `flask`/`fastapi` dependencies without discussion.
- **Shell**: `set -euo pipefail` at the top of every script. No `bash` features
  beyond 5.x.

## Adding a new guest service

1. Add `packages/<name>.py` and `packages/<name>.nix` (the `.nix` just
   `readFile`s the `.py` so the rootfs is reproducible from a single source).
2. Mount it from `nix/sidecar-module.nix`.
3. If it exposes admin endpoints, **always** gate them on
   `X-Hebrah-Internal-Secret` matching the env-loaded secret. See
   `packages/hebrah-sidecar-hl7.py` for the pattern.

> Prefer doing this in [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates)
> instead — this repo is frozen.

## Pull requests

1. Fork the repo and create a branch.
2. Run `nix flake check` before pushing.
3. Keep PRs scoped — one template / one service / one launch script change
   per PR is easier to review.
4. If the change is useful for active deployments, consider proposing it on
   `hebrah-vm-templates` instead.

## Security disclosures

See [SECURITY.md](./SECURITY.md). **Please don't** file public issues for
security bugs — email security@hebrah.com instead.