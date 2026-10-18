{
  name = "overwitch-headless";

  nodes.machine = {
    imports = [ ../module.nix ];

    users.users.alice.isNormalUser = true;

    services.pipewire = {
      enable = true;
      jack.enable = true;
    };

    services.overwitch = {
      enable = true;
      user = "alice";
      settings = {
        blocks = 12;
        pipewireProps = ''{ node.group = "pro-audio-0" }'';
      };
    };
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    with subtest("headless package is selected"):
        machine.succeed("command -v overwitch-cli overwitch-service")
        machine.fail("command -v overwitch")

    with subtest("udev rules are installed"):
        machine.succeed("grep -q 1935 /etc/udev/rules.d/91-usb-elektron.rules")

    with subtest("service starts at boot through lingering"):
        machine.succeed("test -e /var/lib/systemd/linger/alice")
        machine.wait_for_unit("user@1000.service")
        machine.wait_for_unit("overwitch.service", "alice")

    with subtest("preferences are enforced"):
        prefs = "/home/alice/.config/overwitch/preferences.json"
        machine.succeed(f"test -L {prefs}")
        settings = json.loads(machine.succeed(f"cat {prefs}"))
        assert settings == {"blocks": 12, "pipewireProps": '{ node.group = "pro-audio-0" }'}, settings

    with subtest("service answers on the session bus"):
        machine.succeed(
            "su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 busctl --user call "
            "io.github.dagargo.OverwitchService /io/github/dagargo/OverwitchService "
            "io.github.dagargo.OverwitchService GetState'"
        )
  '';
}
