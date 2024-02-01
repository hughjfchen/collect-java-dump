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
        # main working hourse
        go() {
          local MYPID
          local SECONDSTOSLEEP
          local FULLEXE
          local PROCESSWD
          local PROCESSUSER
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
          SECONDSTOSLEEP=30

          # we only support Linux
          [ "Linux" != "$(uname)" ] && echo "This script only supports Linux currently" && exit 1

          [ "$#" -ge 2 ] && SECONDSTOSLEEP="$2"

          # is it a valid PID?
          [ ! -e /proc/"$MYPID" ] && echo "invalid PID $MYPID" && exit 125

          FULLEXE="$(readlink -f /proc/"$MYPID"/exe)"

          [ "$(echo "$FULLEXE" | awk -F"/" '{print $NF}')" != "java" ] && echo "the process $MYPID not a java process" && exit 125

          PROCESSWD="$(pwdx "$MYPID" | awk '{print $NF}')"
          PROCESSUSER="$(ps -eo user,pid | awk -v mypid="$MYPID" '$2==mypid {print $1}')"
          JVMNAME="$($FULLEXE -XshowSettings:properties -version 2>&1 | awk -F' = ' '/java.vm.name/ {print $2}')"

          # get the jvm type
          # TODO: shall we add a IBM J9 type? Not sure, leave it for now. 20220623
          JVMTYPE=""
          for THEJVMTYPE in "OpenJDK" "HotSpot" "OpenJ9"
          do
            if echo "$JVMNAME" | grep "$THEJVMTYPE" > /dev/null; then
               JVMTYPE="$THEJVMTYPE"
            fi
          done

          WASPROCESS="$(ps -eo pid,cmd|awk -v mypid="$MYPID" '$1==mypid {print $0}'|grep -w "com.ibm.ws.bootstrap.WSLauncher")"
          # only support the list JVM or WAS
          if  [ "X$JVMTYPE" == "X" ] && [ "X$WASPROCESS" == "X" ]; then
            echo "Process $MYPID with JVM type $JVMNAME not supported or not a WebSphere Application Server process either, abort."
            exit 110
          fi

          DUMPDATE=$(date "+%Y%m%d")
          DUMPTIME=$(date "+%H%M%S")
          # looks like jattach can support HostSpot VM and OpenJ9 VM,
          # so use jattach to generate dumps for both types of JVM
          # only WebSphere with non-OpenJ9 VM is an exception.
          if [ "X$WASPROCESS" != "X" ] && [ "X$JVMTYPE" != "XOpenJ9" ]; then
             if [ "$PROCESSUSER" == "$(id -nu)" ]; then
                kill -3 "$MYPID"
             else
                sudo su --shell /usr/bin/bash --command "kill -3 $MYPID" "$PROCESSUSER"
             fi

             # need to wait some time for the dump files finishing generated
             sleep "$SECONDSTOSLEEP"

             # now find the generated dumps
             # the order to search is ENV IBM_XXXXDIR -> WorkingDir -> ENV TMPDIR -> /tmp
             # under environment varibale IBM_JAVACOREDIR/IBM_HEAPDUMPDIR/TMPDIR, the working directory of the process or /tmp
             ENV_IBM_JAVACOREDIR="$(strings /proc/"$MYPID"/environ | awk -F'=' '/IBM_JAVACOREDIR/ {print $2}')"
             ENV_IBM_HEAPDUMPDIR="$(strings /proc/"$MYPID"/environ | awk -F'=' '/IBM_HEAPDUMPDIR/ {print $2}')"
             ENV_TMPDIR="$(strings /proc/"$MYPID"/environ | awk -F'=' '/TMPDIR/ {print $2}')"

             # notice that the search path order is really very important.
             JAVACORESEARCHDIR=""
             for THEJAVACORESEARCHDIR in "/tmp" "$ENV_TMPDIR" "$PROCESSWD" "$ENV_IBM_JAVACOREDIR"
             do
                if [ "X$THEJAVACORESEARCHDIR" != "X" ] && [ -d "$THEJAVACORESEARCHDIR" ]; then
                   JAVACORESEARCHDIR="$THEJAVACORESEARCHDIR"
                fi
             done

             HEAPDUMPSEARCHDIR=""
             for THEHEAPDUMPSEARCHDIR in "/tmp" "$ENV_TMPDIR" "$PROCESSWD" "$ENV_IBM_HEAPDUMPDIR"
             do
                if [ "X$THEHEAPDUMPSEARCHDIR" != "X" ] && [ -d "$THEHEAPDUMPSEARCHDIR" ]; then
                   HEAPDUMPSEARCHDIR="$THEHEAPDUMPSEARCHDIR"
                fi
             done

             THREADDUMPFILE=$(find "$JAVACORESEARCHDIR" ! -path "$JAVACORESEARCHDIR" -prune -name "javacore.$DUMPDATE.*.$MYPID.*" -print0 | xargs -r0 ls -t | head -1)
             HEAPDUMPFILE=$(find "$HEAPDUMPSEARCHDIR" ! -path "$HEAPDUMPSEARCHDIR" -prune -name "heapdump.$DUMPDATE.*.$MYPID.*" -print0 | xargs -r0 ls -t | head -1)

             if [ "X$THREADDUMPFILE" == "X" ] && [ "X$HEAPDUMPFILE" == "X" ]; then
                 echo "cannot find the generated java dump files for WebSphere"
                 exit 122
             else
                 echo "$THREADDUMPFILE"
                 echo "$HEAPDUMPFILE"
             fi
          else
             if [ "$JVMTYPE" == "OpenJ9" ]; then
                THREADDUMPFILE="/tmp/javacore.$DUMPDATE.$DUMPTIME.$MYPID.txt"
                HEAPDUMPFILE="/tmp/heapdump.$DUMPDATE.$DUMPTIME.$MYPID.phd"
             else
                THREADDUMPFILE="/tmp/threaddump.$MYPID.$DUMPDATE.$DUMPTIME.threaddump"
                HEAPDUMPFILE="/tmp/heapdump.$MYPID.$DUMPDATE.$DUMPTIME.hprof"
             fi
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
                 echo "cannot find the generated java dump files"
                 exit 122
             fi
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
        else
           echo "Usage: collect-java-dump command collect <Java Process PID> [Seconds to wait for dump finishing generated, default to 30 if not provided]"
           exit 129
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
