{ config, lib, pkgs, env, ... }:

{
  imports = [ ];

  options = {
    collector = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          To enable the config for collector.
        '';
      };
      "command" = lib.mkOption {
        type = lib.types.enum [ "Start" "Stop" ];
        default = "Start";
        example = "Stop";
        description = ''
          The command for the collector.
        '';
      };
    };
  };
}
