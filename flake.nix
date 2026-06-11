{
  description = "hebrah connection sidecar — NixOS microVM (local microvm.nix / future AWS Firecracker)";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [
      "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      lib = nixpkgs.lib;
      hostSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      guestSystemForHost = hostSystem:
        if lib.hasSuffix "-darwin" hostSystem then
          if lib.hasPrefix "aarch64" hostSystem then "aarch64-linux" else "x86_64-linux"
        else
          hostSystem;

      mkMicrovmModule = { name, extraModule, hypervisor }:
        { guestSystem, guestPkgs }:
        [
          microvm.nixosModules.microvm
          extraModule
          {
            networking.hostName = name;
            system.stateVersion = "24.11";
            microvm = {
              vcpu = 1;
              mem = 512;
              inherit hypervisor;
              volumes = [
                {
                  mountPoint = "/var";
                  image = "var.img";
                  size = 256;
                }
              ];
              interfaces = [
                { type = "user"; id = "eth0"; mac = "02:fc:00:00:00:01"; }
              ];
              extraArgsScript = "${guestPkgs.writeShellScript "hebrah-extra-args" ''
                set -euo pipefail
                CONFIG_DIR="''${HEBRAH_VM_CONFIG_DIR:?HEBRAH_VM_CONFIG_DIR required}"
                PORT="''${HEBRAH_HEALTH_HOST_PORT:?HEBRAH_HEALTH_HOST_PORT required}"
                HYP="${hypervisor}"
                if [ "$HYP" = "qemu" ]; then
                  echo "-netdev user,id=hebrah0,hostfwd=tcp:127.0.0.1:''${PORT}-:8080"
                  echo "-device virtio-net-pci,netdev=hebrah0"
                  echo "-virtfs local,path=''${CONFIG_DIR},mount_tag=hebrah-config,security_model=mapped,id=hebrahconfig"
                elif [ "$HYP" = "vfkit" ]; then
                  echo "--device virtio-fs,sharedDir=''${CONFIG_DIR},mountTag=hebrah-config"
                fi
              ''}";
            };
          }
        ];

      mkGuestConfig = { name, extraModule, hypervisor }:
        guestSystem:
        let
          guestPkgs = nixpkgs.legacyPackages.${guestSystem};
        in
        nixpkgs.lib.nixosSystem {
          system = guestSystem;
          modules = mkMicrovmModule {
            inherit name extraModule hypervisor;
          } { inherit guestSystem guestPkgs; };
        };

      mkHostPackages = hostSystem:
        let
          guestSystem = guestSystemForHost hostSystem;
          pkgs = nixpkgs.legacyPackages.${hostSystem};
          hypervisor = "qemu";
          sidecarCfg = mkGuestConfig {
            name = "hebrah-sidecar";
            extraModule = ./nix/sidecar-module.nix;
            inherit hypervisor;
          } guestSystem;
          clinicCfg = mkGuestConfig {
            name = "hebrah-clinic";
            extraModule = ./nix/clinic-simulator-module.nix;
            hypervisor = "qemu";
          } guestSystem;
          sidecarRunner = sidecarCfg.config.microvm.declaredRunner;
          clinicRunner = clinicCfg.config.microvm.declaredRunner;
          mkLauncher = { runner, cfgName, runnerDerivation }:
            pkgs.writeShellScriptBin "hebrah-${cfgName}-launcher" ''
              set -euo pipefail
              CONFIG_DIR="''${HEBRAH_VM_CONFIG_DIR:?HEBRAH_VM_CONFIG_DIR required}"
              PIDFILE="''${HEBRAH_VM_PIDFILE:?HEBRAH_VM_PIDFILE required}"
              LOGFILE="''${HEBRAH_VM_LOGFILE:-$CONFIG_DIR/vm.log}"
              mkdir -p "$CONFIG_DIR"
              RUNNER="$(${pkgs.findutils}/bin/find "${runnerDerivation}/bin" -type f | ${pkgs.coreutils}/bin/head -n1)"
              if [ ! -x "$RUNNER" ]; then
                echo "microvm runner not found in ${runnerDerivation}/bin" >&2
                exit 1
              fi
              nohup "$RUNNER" >"$LOGFILE" 2>&1 &
              echo $! >"$PIDFILE"
              echo "started ${cfgName} pid=$(cat "$PIDFILE") config=$CONFIG_DIR"
            '';
        in
        {
          default = self.packages.${hostSystem}.sidecar-launcher;

          sidecar-microvm = sidecarRunner;
          clinic-simulator = clinicRunner;

          sidecar-launcher = mkLauncher {
            cfgName = "sidecar";
            runnerDerivation = sidecarRunner;
            runner = sidecarRunner;
          };

          clinic-launcher = mkLauncher {
            cfgName = "clinic";
            runnerDerivation = clinicRunner;
            runner = clinicRunner;
          };

          sidecar-rootfs = sidecarCfg.config.microvm.buildRootfs or pkgs.runCommand "sidecar-rootfs-placeholder" { } ''
            echo "build on linux guest eval" > $out
          '';
        };

    in
    {
      nixosConfigurations = {
        sidecar = mkGuestConfig {
          name = "hebrah-sidecar";
          extraModule = ./nix/sidecar-module.nix;
          hypervisor = "qemu";
        } "x86_64-linux";
        clinic-simulator = mkGuestConfig {
          name = "hebrah-clinic";
          extraModule = ./nix/clinic-simulator-module.nix;
          hypervisor = "qemu";
        } "x86_64-linux";
      };

      packages = lib.genAttrs hostSystems (hostSystem: mkHostPackages hostSystem);

      devShells = lib.genAttrs hostSystems (hostSystem:
        let pkgs = nixpkgs.legacyPackages.${hostSystem};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ nix nixfmt-classic jq curl wireguard-tools ];
            shellHook = ''
              echo "hebrah-sidecar dev shell (${hostSystem})"
              echo "  nix build .#sidecar-launcher"
            '';
          };
        });
    };
}
