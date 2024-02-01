self: prev:

# java surgery packages
# this can be used to support IBM J9 VM dump
# provided by IBM as is
prev.stdenv.mkDerivation {
  name = "java-surgery";
  version = "1.1.20220516";
  src = builtins.fetchurl {
    url =
      "https://public.dhe.ibm.com/software/websphere/appserv/support/tools/surgery/surgery.jar";
    sha256 = "";
  };
  dontBuild = true;
  dontUnpack = true;
  unpackPhase = "";
  installPhase = ''
    mkdir -p $out/share/java
    cp $src $out/share/java/
  '';
}
