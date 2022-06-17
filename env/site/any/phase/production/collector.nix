{ config, lib, pkgs, ... }:
let envSubM = import ../../../../env.nix { inherit config lib pkgs; };
in {
  imports = [ ];

  options = {
    collector = lib.mkOption {
      type = lib.types.submodule envSubM;
      description = ''
        The deploy target host env.
      '';
    };
  };

  config = {
    collector = rec {
      hostName = "localhost";
      dnsName = "localhost";
      ipAddress = "127.0.0.1";
      processUser = "jacollectoruser";
      isSystemdService = false;
      runDir = "/var/${processUser}/run";
      dataDir = "/var/${processUser}/data";
    };
  };
}
