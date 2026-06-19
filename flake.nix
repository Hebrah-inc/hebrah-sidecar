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

      # Per-VM host ports are chosen at runtime (HEBRAH_*_HOST_PORT). microvm.forwardPorts
      # is eval-time static, so QEMU user netdev + hostfwd stay in extraArgsScript — do not
      # also set microvm.interfaces for qemu (would duplicate netdevs).
      hebrahQemuExtraArgsScript = hypervisor: guestPkgs:
        guestPkgs.writeShellScript "hebrah-extra-args" ''
          set -euo pipefail
          CONFIG_DIR="''${HEBRAH_VM_CONFIG_DIR:?HEBRAH_VM_CONFIG_DIR required}"
          PORT="''${HEBRAH_HEALTH_HOST_PORT:?HEBRAH_HEALTH_HOST_PORT required}"
          WB_PORT="''${HEBRAH_WRITEBACK_HOST_PORT:-$((PORT + 1))}"
          HL7_PORT="''${HEBRAH_HL7_HOST_PORT:-$((PORT + 2))}"
          MLLP_PORT="''${HEBRAH_MLLP_HOST_PORT:-$((PORT + 3))}"
          HYP="${hypervisor}"
          if [ "$HYP" = "qemu" ]; then
            echo "-netdev user,id=hebrah0,hostfwd=tcp:127.0.0.1:''${PORT}-:8080,hostfwd=tcp:127.0.0.1:''${WB_PORT}-:8082,hostfwd=tcp:127.0.0.1:''${HL7_PORT}-:8083,hostfwd=tcp:127.0.0.1:''${MLLP_PORT}-:2575"
            echo "-device virtio-net-pci,netdev=hebrah0"
            echo "-fsdev local,id=hebrahconfig,path=''${CONFIG_DIR},security_model=mapped-xattr,fmode=0644,dmode=0755,writeout=immediate"
            echo "-device virtio-9p-pci,mount_tag=hebrah-config,fsdev=hebrahconfig"
          elif [ "$HYP" = "vfkit" ]; then
            echo "--device virtio-fs,sharedDir=''${CONFIG_DIR},mountTag=hebrah-config"
          fi
        '';

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
              mem = 1024;
              cpu = "max";
              inherit hypervisor;
              qemu.machine = "virt";
              volumes = [
                {
                  mountPoint = "/var";
                  image = "var.img";
                  size = 256;
                }
              ];
              interfaces = guestPkgs.lib.optionals (hypervisor != "qemu") [
                { type = "user"; id = "eth0"; mac = "02:fc:00:00:00:01"; }
              ];
              extraArgsScript = "${hebrahQemuExtraArgsScript hypervisor guestPkgs}";
              balloon = false;
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
          hl7Pkg = pkgs.callPackage ./packages/hebrah-sidecar-hl7.nix { };
          mkLauncher = { runner, cfgName, runnerDerivation }:
            pkgs.writeShellScriptBin "hebrah-${cfgName}-launcher" ''
              set -euo pipefail
              CONFIG_DIR="''${HEBRAH_VM_CONFIG_DIR:?HEBRAH_VM_CONFIG_DIR required}"
              PIDFILE="''${HEBRAH_VM_PIDFILE:?HEBRAH_VM_PIDFILE required}"
              LOGFILE="''${HEBRAH_VM_LOGFILE:-$CONFIG_DIR/vm.log}"
              mkdir -p "$CONFIG_DIR"
              RUNNER="${runnerDerivation}/bin/microvm-run"
              if [ ! -x "$RUNNER" ]; then
                RUNNER="$(${pkgs.findutils}/bin/find "${runnerDerivation}/bin" -maxdepth 1 -executable -print -quit)"
              fi
              if [ ! -x "$RUNNER" ]; then
                echo "microvm runner not found in ${runnerDerivation}/bin" >&2
                exit 1
              fi
              cd "$CONFIG_DIR"
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

          hebrah-sidecar-hl7 = hl7Pkg;
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
