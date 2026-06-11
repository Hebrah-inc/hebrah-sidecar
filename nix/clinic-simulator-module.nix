{ config, lib, pkgs, ... }:

let
  clinicServer = pkgs.writeScript "hebrah-clinic-fhir" ''
    #!${pkgs.python3}/bin/python3
    ${lib.readFile ../packages/clinic-fhir-server.py}
  '';
in
{
  options.services.hebrah-clinic-simulator = {
    enable = lib.mkEnableOption "hebrah clinic FHIR simulator microVM";
  };

  config = {
    services.hebrah-clinic-simulator.enable = lib.mkDefault true;

    systemd.services.hebrah-clinic-fhir = {
      description = "Stub clinic FHIR endpoint on :8081";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        ExecStart = clinicServer;
      };
    };

    networking.firewall.allowedTCPPorts = [ 8081 ];
  };
}
