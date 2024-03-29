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
  mk-collect-java-dump = { jattachPkg, ... }:
    pkgs.writeTextFile rec {
      name = "collect-java-dump";
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!/usr/bin/env bash

        # some utility functions
        is_uint() {
          case $1 in
            '''|*[!0-9]*) return 1 ;;
            *) return 0 ;;
          esac
        }

        # main working hourse
        go() {
          local MYPID
          local SECONDSTOSLEEP
          local FULLEXE
          local PROCESSWD
          local PROCESSUSER
          local JVMVERSION
          local JVMNAME
          local JVMTYPE
          local DUMPDATE
          local DUMPTIME
          local ENV_IBM_JAVACOREDIR
          local ENV_IBM_HEAPDUMPDIR
          local ENV_TMPDIR
          local THREADDUMPFILE
          local HEAPDUMPFILE


          MYPID=$1
          SECONDSTOSLEEP=5

          [ "$#" -eq 2 ] && SECONDSTOSLEEP="$2"

          # is it a valid PID?
          [ ! -e /proc/"$MYPID" ] && echo "invalid PID $MYPID" && exit 125

          FULLEXE="$(readlink -f /proc/"$MYPID"/exe)"

          [ "$(echo "$FULLEXE" | awk -F"/" '{print $NF}')" != "java" ] && echo "the process $MYPID not a java process" && exit 125

          PROCESSWD="$(pwdx "$MYPID" | awk '{print $NF}')"
          PROCESSUSER="$(ps -eo user,pid | awk -v mypid="$MYPID" '$2==mypid {print $1}')"
          JVMNAME="$($FULLEXE -version 2>&1 | grep -v grep | grep ' VM ' | grep 'build')"

          # get the jvm type
          # TODO: shall we add a IBM J9 type? Not sure, leave it for now. 20220623
          JVMTYPE=""
          for THEJVMTYPE in "OpenJDK" "HotSpot" "OpenJ9" "IBM J9"
          do
            if echo "$JVMNAME" | grep "$THEJVMTYPE" > /dev/null; then
               JVMTYPE="$THEJVMTYPE"
            fi
          done

          DUMPDATE=$(date "+%Y%m%d")
          DUMPTIME=$(date "+%H%M%S")

          # looks like jattach can support OpenJDK/HostSpot VM and OpenJ9 VM,
          # so use jattach to generate dumps for these three types of JVM
          # only IBM J9 VM is an exception.
          case "$JVMTYPE" in
            "OpenJDK"|"HotSpot")
               THREADDUMPFILE="/tmp/threaddump.$MYPID.$DUMPDATE.$DUMPTIME.threaddump"
               HEAPDUMPFILE="/tmp/heapdump.$MYPID.$DUMPDATE.$DUMPTIME.hprof"
               if [ "$PROCESSUSER" == "$(id -nu)" ]; then
                 ${jattachPkg}/bin/jattach "$MYPID" threaddump > "$THREADDUMPFILE"
                 ${jattachPkg}/bin/jattach "$MYPID" dumpheap "$HEAPDUMPFILE" > /dev/null
               else
                 sudo su --shell /usr/bin/bash --command "${jattachPkg}/bin/jattach $MYPID threaddump > $THREADDUMPFILE" "$PROCESSUSER"
                 sudo su --shell /usr/bin/bash --command "${jattachPkg}/bin/jattach $MYPID dumpheap $HEAPDUMPFILE > /dev/null" "$PROCESSUSER"
               fi
               if [ -e "$THREADDUMPFILE" ] && [ -e "$HEAPDUMPFILE" ]; then
                 echo "$THREADDUMPFILE"
                 echo "$HEAPDUMPFILE"
               else
                 echo "cannot find the generated javadump/heapdump files"
                 exit 122
               fi
               ;;
            "OpenJ9|IBM J9")
               THREADDUMPFILE="/tmp/javacore.$DUMPDATE.$DUMPTIME.$MYPID.txt"
               HEAPDUMPFILE="/tmp/heapdump.$DUMPDATE.$DUMPTIME.$MYPID.phd"
               if [ "$PROCESSUSER" == "$(id -nu)" ]; then
                 ${jattachPkg}/bin/jattach "$MYPID" threaddump > "$THREADDUMPFILE"
                 ${jattachPkg}/bin/jattach "$MYPID" dumpheap "$HEAPDUMPFILE" > /dev/null
               else
                 sudo su --shell /usr/bin/bash --command "${jattachPkg}/bin/jattach $MYPID threaddump > $THREADDUMPFILE" "$PROCESSUSER"
                 sudo su --shell /usr/bin/bash --command "${jattachPkg}/bin/jattach $MYPID dumpheap $HEAPDUMPFILE > /dev/null" "$PROCESSUSER"
               fi
               if [ -e "$THREADDUMPFILE" ] && [ -e "$HEAPDUMPFILE" ]; then
                 echo "$THREADDUMPFILE"
                 echo "$HEAPDUMPFILE"
               else
                 echo "cannot find the generated javadump/heapdump files"
                 exit 122
               fi
               ;;
            *) echo "Not supported JVM type, currently only support OpenJDK, HotSpot, OpenJ9 and IBM J9"
               exit 110
               ;;
          esac

        }

        # check command line args
        # the first command line arg is the path to a config file
        # and the second command line arg is the command, should be "collect"
        # we leave it as if for now

        if [ "$#" -eq 3 ] || [ "$#" -eq 4 ]; then

           # only when we get the command "collect"
           if [ "$2" == "collect" ]; then

              # currently, only linux is supported
              [ "$(uname -s)" != "Linux" ] && echo "This is a non-linux machine. Only Linux is supported." && exit 128

              # this script need to be run with root or having sudo permission
              [ $EUID -ne 0 ] && ! sudo echo >/dev/null 2>&1 && echo "need to run with root or sudo without password prompt" && exit 127

              # if the given argument is not a integer PID, try to treat it as a WebSphere application server name
              # and search the appropriate PID for that server
              GIVEN_PID=""
              if is_uint "$3"; then
                GIVEN_PID="$3"
              else
                # search the PID using the given argument as a WAS server name
                WAS_PID="$(ps -eo pid,cmd|grep -w "com.ibm.ws.bootstrap.WSLauncher"|awk -v myserver="$3" '$NF==myserver {print $1}')"
                if [ "X$WAS_PID" == "X" ]; then
                  echo "The given argument neither a PID nor a valid WebSphere application server name, abort."
                  exit 130
                else
                  GIVEN_PID="$WAS_PID"
                fi
              fi

              if [ "$#" -eq 4 ]; then
                go "$GIVEN_PID" "$4"
              else
                go "$GIVEN_PID"
              fi
           else
             # for other command, just ignore
             exit 0
           fi
        else
           if [ "$2" == "collect" ]; then
             echo "Usage: collect-java-dump <Java Process PID|WebSphere Application Server Name> [Seconds to wait for dump finishing generated, default to 5 if not provided]"
             exit 129
           else
             # ignore other command for now
             exit 0
           fi
        fi

      '';
    };
in {
  # inherit the pkgs package set so that others importing this function can use it
  inherit pkgs;

  # nativePkgs.lib.recurseIntoAttrs, just a bit more explicilty.
  recurseForDerivations = true;

  inherit mk-collect-java-dump;

  # use writeScriptBin instead to reduce the packed bundle size
  collect-java-dump = mk-collect-java-dump { jattachPkg = pkgs.jattach; };
}
