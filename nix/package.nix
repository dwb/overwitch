{
  lib,
  stdenv,
  autoreconfHook,
  pkg-config,
  gettext,
  wrapGAppsHook4,
  libusb1,
  libjack2,
  libsamplerate,
  libsndfile,
  glib,
  json-glib,
  systemdLibs,
  gtk4,
  cunit,
  withGui ? true,
}:

stdenv.mkDerivation {
  pname = if withGui then "overwitch" else "overwitch-headless";
  version = import ./version.nix;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../configure.ac
      ../Makefile.am
      ../AUTHORS
      ../COPYING
      ../ChangeLog
      ../INSTALL
      ../NEWS
      ../README
      ../THANKS
      ../po
      ../res
      ../src
      ../systemd
      ../test
      ../udev
    ];
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    gettext
  ]
  ++ lib.optional withGui wrapGAppsHook4;

  buildInputs = [
    libusb1
    libjack2
    libsamplerate
    libsndfile
    glib
    json-glib
    systemdLibs
    cunit
  ]
  ++ lib.optional withGui gtk4;

  configureFlags = [
    "--with-systemduserconfdir=${placeholder "out"}/share/systemd/user"
  ]
  ++ lib.optional (!withGui) "CLI_ONLY=yes";

  enableParallelBuilding = true;
  doCheck = true;

  # Only the GTK application needs the GApps wrapper.
  dontWrapGApps = true;

  # The systemd and udev directories are not part of the install target upstream.
  postInstall = ''
    install -Dm644 systemd/overwitch.service -t $out/share/systemd/user
    substituteInPlace $out/share/systemd/user/overwitch.service \
      --replace-fail "ExecStart=overwitch-service" "ExecStart=$out/bin/overwitch-service"

    install -Dm644 udev/91-usb-elektron.rules -t $out/lib/udev/rules.d
    install -Dm644 udev/91-usb-elektron.hwdb -t $out/lib/udev/hwdb.d

    rm -f $out/share/icons/hicolor/icon-theme.cache
  ''
  + lib.optionalString (!withGui) ''
    # The desktop entry and icons belong to the GUI, which is not built.
    rm -r $out/share/applications $out/share/icons
  '';

  postFixup = lib.optionalString withGui ''
    wrapGApp $out/bin/overwitch
  '';

  meta = {
    description =
      "Overbridge 2 device client for JACK" + lib.optionalString (!withGui) " (command line tools only)";
    longDescription = ''
      Overwitch is a set of JACK clients for Overbridge 2 devices by Elektron.
      It includes a hotplug D-Bus/systemd service, a single device CLI client
      and recording and playing utilities${lib.optionalString withGui ", plus a GTK4 GUI"}.
    '';
    homepage = "https://github.com/dagargo/overwitch";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = if withGui then "overwitch" else "overwitch-cli";
  };
}
