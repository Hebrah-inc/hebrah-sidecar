# Security policy

## Reporting a vulnerability

If you discover a security vulnerability in `hebrah-sidecar`, please report it
privately to **security@hebrah.com** (or open a private security advisory
via GitHub: <https://github.com/Hebrah-inc/hebrah-sidecar/security/advisories/new>).

Please **do not** file a public issue for suspected vulnerabilities.

Include as much of the following as you can:

- A clear description of the issue and its impact (RCE, privilege escalation,
  information disclosure, denial of service, etc.).
- Reproduction steps or a proof-of-concept.
- The affected version (`git rev-parse HEAD` is great).
- Your assessment of exploitability and affected configurations
  (e.g. "only when `HEBRAH_INTERNAL_SECRET` is unset").

We aim to acknowledge reports within **3 business days** and to coordinate
disclosure timelines with reporters.

> **This repo is legacy.** Active development lives in
> [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates).
> New security reports against the sidecar templates should prefer that
> repo unless the issue is specific to the legacy `microvm.nix` launcher in
> this flake.

## What this repo protects against

`hebrah-sidecar` ships the legacy NixOS microVM template + launcher used by
`HYPERVISOR=microvm-nix`. The threat model for an operator who runs this
launcher is roughly:

| Boundary | Mechanism |
|----------|-----------|
| Sidecar → control plane (`POST /v1/internal/sidecar/events`) | `HEBRAH_INTERNAL_SECRET` (shared secret) on `X-Hebrah-Internal-Secret` header. The sidecar's writeback + HL7 services only accept internal events when the header matches. |
| Guest → host via QEMU 9p share | `security_model=mapped-xattr` on `HEBRAH_VM_CONFIG_DIR`. Guest-created files are mapped to the QEMU user (`ubuntu` on EC2); `passthrough` is rejected because it requires privileged QEMU. |
| Guest port exposure | QEMU user netdev + `hostfwd` only forwards the documented sidecar ports (8080 health, 8082 write-back, 8083 HL7, 2575 MLLP) to localhost; the guest has no public IP. |

## What this repo does NOT protect against

This repo is **not** a security boundary on its own. An operator must also:

- Run the orchestrator with proper isolation (separate `HEBRAH_VM_CONFIG_DIR`
  per VM, no privileged QEMU mode).
- Rotate `HEBRAH_INTERNAL_SECRET` between golden images and never bake a
  long-lived secret into the flake. Treat it like a per-environment shared
  secret, not a long-term API key.
- Keep `microvm.nix` and `nixpkgs` up to date — see [CONTRIBUTING.md](./CONTRIBUTING.md).
- Migrate to [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates)
  for new deployments — that repo carries the active security work
  (hot-claim handoff FSM, snapshot env hardening, tap-bound admin helpers).

For the platform-level threat model (PATs, API keys, webhook signatures,
control-plane posture), see
[`hebrah-mcp-host/SECURITY.md`](https://github.com/Hebrah-inc/hebrah-mcp-host/blob/main/SECURITY.md).

## Supported versions

| Version | Supported |
|---------|-----------|
| `main` branch HEAD | ✅ (best effort, legacy) |
| Anything older | No |

This repo is in **maintenance-only** mode. New features and security hardening
land in `hebrah-vm-templates`.

## Disclosure timeline

We follow a roughly 90-day responsible-disclosure window. We will coordinate
with reporters on a release date and credit them in the commit / advisory.