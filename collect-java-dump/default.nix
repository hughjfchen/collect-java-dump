let
  sources = import ./nix/sources.nix;
  # Fetch the latest haskell.nix and import its default.nix
  haskellNix = import sources."haskell.nix" { };
  # haskell.nix provides access to the nixpkgs pins which are used by our CI, hence
  # you will be more likely to get cache hits when using these.
  # But you can also just use your own, e.g. '<nixpkgs>'
  #nixpkgsSrc = if haskellNix.pkgs.stdenv.hostPlatform.isDarwin then sources.nixpkgs-darwin else haskellNix.sources.nixpkgs-2111;
  # no need to check platform now
  nixpkgsSrc = haskellNix.sources.nixpkgs-2111;
  # haskell.nix provides some arguments to be passed to nixpkgs, including some patches
  # and also the haskell.nix functionality itself as an overlay.
  nixpkgsArgs = haskellNix.nixpkgsArgs;
in { nativePkgs ? import nixpkgsSrc (nixpkgsArgs // {
  overlays = nixpkgsArgs.overlays ++ [ (import ./nix/overlay) ];
}), haskellCompiler ? "ghc8107", customModules ? [ ] }:
let
  pkgs = nativePkgs;
  # 'cabalProject' generates a package set based on a cabal.project (and the corresponding .cabal files)
in rec {
  # inherit the pkgs package set so that others importing this function can use it
  inherit pkgs;

  # nativePkgs.lib.recurseIntoAttrs, just a bit more explicilty.
  recurseForDerivations = true;

  collect-java-dump = pkgs.writeShellApplication {
    name = "collect-java-dump";
    runtimeInputs = [ pkgs.coreutils pkgs.jattach ];
    text = ''
      # main working hourse
      go() {
        local MYPID
        local SECONDSTOSLEEP
        local FULLEXE
        local PROCESSWD
        local PROCESSUSER
        local JDKTYPE
        local DUMPDATE
        local DUMPTIME

        MYPID=$1
        SECONDSTOSLEEP=30
        [ "$#" -ge 2 ] && SECONDSTOSLEEP="$2"

        # is it a valid PID?
        [ ! -e /proc/"$MYPID" ] && echo "invalid PID $MYPID" && exit 125

        FULLEXE="$(readlink -f /proc/"$MYPID"/exe)"

        PROCESSWD="$(pwdx "$MYPID" | awk '{print $NF}')"
        PROCESSUSER="$(ps -eo user,pid | awk -v mypid="$MYPID" '$2==mypid {print $1}')"
        JDKTYPE="$($FULLEXE -version 2>&1 | grep -i ibm > /dev/null && echo IBMJAVA || echo NONIBMJAVA)"

        DUMPDATE=$(date "+%Y%m%d")
        DUMPTIME=$(date "+%H%M%S")
        if [ "$JDKTYPE" == "IBMJAVA" ]; then
           sudo su --shell /usr/bin/bash --command "kill -3 $MYPID"
           # need to wait some time for the dump files finishing generated
           sleep "$SECONDSTOSLEEP"
           # now find the generated dumps
           # under the working directory of the process or /tmp
           find "$PROCESSWD" ! -path "$PROCESSWD" -prune -name "*.$MYPID.$DUMPDATE.*" -print0 | xargs -r ls -t | head -2
           find "$PROCESSWD" ! -path "$PROCESSWD" -prune -name "*.$DUMPDATE.*.$MYPID.*" -print0 | xargs -r ls -t | head -2
           find /tmp ! -path /tmp -prune -name "*.$MYPID.$DUMPDATE.*" -print0 | xargs -r ls -t | head -2
           find /tmp ! -path /tmp -prune -name "*.$DUMPDATE.*.$MYPID.*" -print0 | xargs -r ls -t | head -2
        else
          THREADDUMPFILE="/tmp/threaddump.$MYPID.$DUMPDATE.$DUMPTIME.threaddump"
          HEAPDUMPFILE="/tmp/heapdump.$MYPID.$DUMPDATE.$DUMPTIME.hprof"
          sudo su --shell /usr/bin/bash --command "${pkgs.jattach}/bin/jattach $MYPID jcmd Thread.print > $THREADDUMPFILE" "$PROCESSUSER"
          sudo su --shell /usr/bin/bash --command "${pkgs.jattach}/bin/jattach $MYPID jcmd \"GC.heap_dump $HEAPDUMPFILE\"" "$PROCESSUSER"
          echo "$THREADDUMPFILE"
          echo "$HEAPDUMPFILE"
        fi
      }

      # only when we get the command "collect"
      if [ "$#" -ge 2 ]; then
         if [ "$2" == "collect" ]; then
            # currently, only linux is supported
            [ "$(uname -s)" != "Linux" ] && echo "This is a non-linux machine. Only Linux is supported." && exit 128

            # this script need to be run with root or having sudo permission
            [ $EUID -ne 0 ] && ! sudo echo >/dev/null 2>&1 && echo "need to run with root or sudo without password" && exit 127

            # check command line args
            # the first command line arg is the path to a config file
            # and the second command line arg is the command, should be "collect"
            # we leave it as if for now
            if [ "$#" -ge 3 ]; then
               if [ "$#" -ge 4 ]; then
                  go "$3" "$4"
               else
                  go "$3"
               fi
            else
              echo "Usage: collect-java-dump <Java Process PID> [Seconds to wait for dump finishing generated, default to 30 if not provided]"
              exit 129
            fi
         fi
      fi

    '';
  };
}
