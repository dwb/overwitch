{
  name = "overwitch-gui";

  nodes.machine = {
    imports = [ ../module.nix ];

    users.users.alice.isNormalUser = true;

    # Stands in for a desktop environment; this is what gui.enable detects.
    services.graphical-desktop.enable = true;

    services.pipewire = {
      enable = true;
      jack.enable = true;
    };

    services.overwitch = {
      enable = true;
      settings = {
        blocks = 12;
        pipewireProps = ''{ node.group = "pro-audio-0" }'';
      };
    };
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    with subtest("GUI package is selected"):
        machine.succeed("command -v overwitch overwitch-cli")
        machine.succeed("test -e /run/current-system/sw/share/applications/io.github.dagargo.Overwitch.desktop")

    with subtest("nothing lingers or autostarts"):
        machine.fail("test -e /var/lib/systemd/linger/alice")
        machine.succeed("loginctl enable-linger alice")
        machine.wait_for_unit("user@1000.service")
        machine.fail("systemctl --user -M alice@ is-active overwitch.service")

    with subtest("preferences are seeded and writable"):
        prefs = "/home/alice/.config/overwitch/preferences.json"
        machine.succeed(f"test -f {prefs} && ! test -L {prefs}")
        machine.succeed(f"su - alice -c 'test -w {prefs}'")
        settings = json.loads(machine.succeed(f"cat {prefs}"))
        assert settings == {"blocks": 12, "pipewireProps": '{ node.group = "pro-audio-0" }'}, settings

    with subtest("D-Bus activation starts the systemd unit"):
        machine.fail("test -e /run/current-system/sw/share/dbus-1/services/io.github.dagargo.OverwitchService.service")
        # As in the GUI, the call that triggers activation may arrive before
        # the service has registered its object, so retry.
        machine.wait_until_succeeds(
            "su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 busctl --user call "
            "io.github.dagargo.OverwitchService /io/github/dagargo/OverwitchService "
            "io.github.dagargo.OverwitchService GetState'"
        )
        machine.wait_for_unit("overwitch.service", "alice")
  '';
}
