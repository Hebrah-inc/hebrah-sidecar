{ config, lib, pkgs, ... }:

let
  healthPkg = pkgs.callPackage ../packages/hebrah-sidecar-health.nix { };
in
{
  options.services.hebrah-sidecar = {
    enable = lib.mkEnableOption "hebrah connection sidecar agent";
  };

  config = {
    services.hebrah-sidecar.enable = lib.mkDefault true;

    systemd.tmpfiles.rules = [
      "d /hebrah-config 0755 root root -"
    ];

    systemd.services.hebrah-sidecar-config = {
      description = "Load hebrah sidecar config from virtiofs share";
      wantedBy = [ "multi-user.target" ];
      before = [ "hebrah-sidecar-health.service" "hebrah-sidecar-wg.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "hebrah-config-check" ''
          set -euo pipefail
          if [ -f /hebrah-config/hebrah.env ]; then
            cp /hebrah-config/hebrah.env /etc/hebrah.env
          fi
        '';
      };
    };

    systemd.services.hebrah-sidecar-health = {
      description = "hebrah sidecar health HTTP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "hebrah-sidecar-config.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
        Environment = "HEBRAH_CONFIG_DIR=/hebrah-config";
        ExecStart = "${healthPkg}/bin/hebrah-sidecar-health";
      };
    };

    networking.firewall.allowedTCPPorts = [ 8080 ];

    systemd.services.hebrah-sidecar-wg = {
      description = "hebrah sidecar WireGuard interface";
      wantedBy = [ "multi-user.target" ];
      after = [ "hebrah-sidecar-config.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "hebrah-wg-up" ''
          set -euo pipefail
          if [ ! -f /hebrah-config/hebrah.env ]; then
            exit 0
          fi
          # shellcheck disable=SC1091
          source /hebrah-config/hebrah.env
          if [ -z "''${HEBRAH_WG_PRIVATE_KEY:-}" ]; then
            exit 0
          fi
          mkdir -p /etc/wireguard
          umask 077
          cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ''${HEBRAH_WG_PRIVATE_KEY}
Address = 10.8.0.2/32
ListenPort = ''${HEBRAH_WG_LISTEN_PORT:-51820}

EOF
          ${pkgs.wireguard-tools}/bin/wg-quick up wg0 || true
        '';
        ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down wg0";
      };
    };
  };
}
