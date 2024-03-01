{ nativePkgs ? import ./default.nix { }, # the native package set
pkgs ? import ./cross-build.nix { }
, # the package set for corss build, we're especially interested in the fully static binary
site, # the site for release, the binary would deploy to it finally
phase, # the phase for release, must be "local", "test" and "production"
}:
let
  nPkgs = nativePkgs.pkgs;
  sPkgs = pkgs.x86-musl64; # for the fully static build
  lib = nPkgs.lib; # lib functions from the native package set
  pkgName = "my-collect-java-dump";
  innerTarballName = lib.concatStringsSep "." [
    (lib.concatStringsSep "-" [ pkgName site phase ])
    "tar"
    "gz"
  ];

  # define some utility function for release packing ( code adapted from setup-systemd-units.nix )
  deploy-packer = import (builtins.fetchGit { url = "https://github.com/hughjfchen/deploy-packer"; }) {
    inherit lib;
    pkgs = nPkgs;
  };

  # the deployment env
  my-collect-java-dump-env =
    (import (builtins.fetchGit { url = "https://github.com/hughjfchen/deploy-env"; }) { pkgs = nPkgs;
                                                                                 modules = [ ../env/site/${site}/phase/${phase}/collector.nix ];
                                                                               }).env;
  # the config
  my-collect-java-dump-config =
    (import (builtins.fetchGit { url = "https://github.com/hughjfchen/deploy-config"; }) {
      pkgs = nPkgs;
      env = my-collect-java-dump-env;
      modules = [ ../config/site/${site}/phase/${phase}/collector.nix ];
    }).config;

  my-collect-java-dump-config-file = nPkgs.writeTextFile {
    name = lib.concatStringsSep "-" [ pkgName "config" ];
    # generate the key = value format config, refer to the lib.generators for other formats
    text =
      (lib.generators.toKeyValue { }) my-collect-java-dump-config.collector;
  };

  my-collect-java-dump-bin-sh = nPkgs.writeTextFile rec {
    name = lib.concatStringsSep "-" [ pkgName "bin" "sh" ];
    executable = true;
    destination = "/bin/${name}";
    # wrap the executable, suppose it accept a --config commandl ine option to load the config
    text = ''
      #!/usr/bin/env bash
      export PATH="${sPkgs.collect-java-dump}/bin:$PATH"
      ${sPkgs.collect-java-dump.name} --config.file="${my-collect-java-dump-config-file}" "$@"
    '';
  };

in rec {
  inherit nativePkgs pkgs my-collect-java-dump-env my-collect-java-dump-config;

  mk-my-collect-java-dump-reference =
    nPkgs.writeReferencesToFile my-collect-java-dump-bin-sh;

  mk-my-collect-java-dump-deploy-sh = deploy-packer.mk-deploy-sh {
    env = my-collect-java-dump-env.collector;
    payloadPath = my-collect-java-dump-bin-sh;
    inherit innerTarballName;
    execName = "${my-collect-java-dump-bin-sh.name}";
    startCmd = "collect";
    stopCmd = "noop";
  };
  mk-my-collect-java-dump-cleanup-sh = deploy-packer.mk-cleanup-sh {
    env = my-collect-java-dump-env.collector;
    payloadPath = my-collect-java-dump-bin-sh;
    inherit innerTarballName;
    execName = "${my-collect-java-dump-bin-sh.name}";
  };
  mk-my-release-packer = deploy-packer.mk-release-packer {
    referencePath = mk-my-collect-java-dump-reference;
    component = pkgName;
    inherit site phase innerTarballName;
    deployScript = mk-my-collect-java-dump-deploy-sh;
    cleanupScript = mk-my-collect-java-dump-cleanup-sh;
  };
}
