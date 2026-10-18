{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "overwitch-udev";
  version = import ./version.nix;

  src = ../udev;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 91-usb-elektron.rules -t $out/lib/udev/rules.d
    install -Dm644 91-usb-elektron.hwdb -t $out/lib/udev/hwdb.d
    runHook postInstall
  '';

  meta = {
    description = "udev rules and hwdb entries for Elektron Overbridge devices";
    homepage = "https://github.com/dagargo/overwitch";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
