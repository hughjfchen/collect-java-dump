{ defaultPlatformProject ? import ./default.nix { }
, toBuild ? import ./nix/cross-build/systems.nix defaultPlatformProject.pkgs }:
# map through the system list
defaultPlatformProject.pkgs.lib.mapAttrs (_: pkgs: rec {
  # nativePkgs.lib.recurseIntoAttrs, just a bit more explicilty.
  recurseForDerivations = true;

  inherit pkgs;

  jattach =
    pkgs.jattach.overrideAttrs (oldAttrs: { patches = [ ./static.patch ]; });

  collect-java-dump =
    defaultPlatformProject.mk-collect-java-dump { jattachPkg = jattach; java-surgeryPkg = pkgs.java-surgery; };

}) toBuild
