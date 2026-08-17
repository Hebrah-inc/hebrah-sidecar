# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `.gitignore` now excludes Python `__pycache__/`, `*.pyc`, and `*.pyo`. The three `.pyc` files committed in earlier pushes were untracked.
- README relative-link fixes so the standalone GitHub repo doesn't 404 on `../hebrah-vm-templates/` and `../documentation/...` paths.

### Added

- `CONTRIBUTING.md` describing dev setup, scripts, layout, and the (limited) scope of this legacy repo.
- `CODE_OF_CONDUCT.md` (Contributor Covenant v2.1).
- Issue templates (bug report, feature request, docs) and PR template under `.github/`.
- GitHub Actions CI: `nix flake check` + build `sidecar-launcher`.
- OSS discovery badges in README (License, status: LEGACY, NixOS-unstable, GitHub stars + issues).

## [1.0.0] — 2026-06-08

### Added

- Initial open-source release of the legacy Nix flake for the connection sidecar microVM (microvm.nix-based, vfkit on macOS, QEMU on Linux).
- `sidecar-launcher`, `sidecar-microvm`, `clinic-simulator`, `clinic-launcher`, and `sidecar-rootfs` outputs.
- Phase 2 sidecar agents: health (8080), write-back (8082), HL7 HTTP (8083), HL7 MLLP (2575).

> New VM work happens in [`hebrah-vm-templates`](https://github.com/Hebrah-inc/hebrah-vm-templates). This repo only ships patches for the legacy `HYPERVISOR=microvm-nix` cold-`nix run` flow.

[Unreleased]: https://github.com/Hebrah-inc/hebrah-sidecar/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Hebrah-inc/hebrah-sidecar/releases/tag/v1.0.0