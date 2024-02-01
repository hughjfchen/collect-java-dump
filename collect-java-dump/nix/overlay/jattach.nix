self: prev:

# the jattach package
# adapted based on the Makefile of the package source tree
prev.stdenv.mkDerivation rec {
  pname = "jattach";
  version = "2.2";

  src = prev.fetchFromGitHub {
    owner = "apangin";
    repo = "jattach";
    rev = "v${version}";
    sha256 = "xHorLGzTsmU7tHkBRLF8yqx2FlgtNtJg6iYVlXYgRjI=";
  };

  # patch to build static lib, refer to:
  # https://github.com/apangin/jattach/pull/54
  # disable it for now because I do not want to build
  # fully static binary yet.
  # patches = [ ./pr54.patch ];

  buildPhase = ''
    make
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp -R build/* $out/bin
  '';
  # disable test
  doCheck = false;
  dontStrip = false;
  fixupPhase = ''
    find $out/bin -type f -exec patchelf --shrink-rpath '{}' \; -exec strip '{}' \; 2>/dev/null
  '';

}
