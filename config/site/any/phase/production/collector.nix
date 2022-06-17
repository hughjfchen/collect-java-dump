{ config, lib, pkgs, env, ... }:

{
  imports = [ ];

  config =
    lib.mkIf config.collector.enable { collector = { "command" = "Start"; }; };
}
