{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.overwitch;

  json = pkgs.formats.json { };

  pipewire = config.services.pipewire;
  usePipewireJack = pipewire.enable && pipewire.jack.enable;

  # Set by xserver, display managers and every Wayland compositor module.
  # Fall back to the underlying options on releases without it.
  guiDetected =
    config.services.graphical-desktop.enable
      or (config.services.xserver.enable || config.services.displayManager.enable);

  settings = lib.filterAttrs (_: v: v != null) cfg.settings;
  settingsFile = json.generate "overwitch-preferences.json" settings;
  prefsPath = "%h/.config/overwitch/preferences.json";

  tmpfilesRules = [
    "d %h/.config/overwitch 0755 - - -"
  ]
  ++ (
    if cfg.enforceSettings then
      [ "L+ ${prefsPath} - - - - ${settingsFile}" ]
    else
      # Seed only; the GUI owns the file from then on.
      [
        "C ${prefsPath} - - - - ${settingsFile}"
        "z ${prefsPath} 0644 - - -"
      ]
  );

  # D-Bus activation goes through the systemd user unit, so the GUI and the
  # autostarted service are the same instance with the same environment.
  # The session bus searches the system profile before services.dbus.packages,
  # so the package's own Exec-only service file must not be linked there.
  profilePackage = pkgs.symlinkJoin {
    name = "${cfg.package.name}-profile";
    paths = [ cfg.package ];
    postBuild = "rm -rf $out/share/dbus-1";
    inherit (cfg.package) meta;
  };

  dbusService = pkgs.writeTextDir "share/dbus-1/services/io.github.dagargo.OverwitchService.service" ''
    [D-BUS Service]
    Name=io.github.dagargo.OverwitchService
    Exec=${lib.getExe' cfg.package "overwitch-service"}
    SystemdService=overwitch.service
  '';
in
{
  options.services.overwitch = {
    enable = lib.mkEnableOption "Overwitch, a JACK client for Elektron Overbridge 2 devices";

    gui.enable = lib.mkOption {
      type = lib.types.bool;
      default = guiDetected;
      defaultText = lib.literalExpression "config.services.graphical-desktop.enable";
      description = ''
        Whether to install the GTK4 GUI. When disabled, a build without GTK is
        used and Overwitch runs headless: the hotplug service is started with
        the user's systemd instance, lingering is enabled for
        {option}`services.overwitch.user` so it runs from boot, and
        {option}`services.overwitch.settings` are enforced.

        Defaults to whether a graphical session is configured on this system.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { withGui = cfg.gui.enable; };
      defaultText = lib.literalExpression "overwitch (overwitch-headless when gui.enable is false)";
      description = "The Overwitch package to use.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        User whose systemd instance runs `overwitch-service`. Required for
        headless operation. When null, the service is available to every user,
        but is only autostarted if {option}`services.overwitch.autoStart` is set.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.gui.enable;
      defaultText = lib.literalExpression "!config.services.overwitch.gui.enable";
      description = ''
        Whether to start `overwitch-service` with the user's systemd instance.
        Otherwise it is started on demand when the GUI connects over D-Bus.
      '';
    };

    linger = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.gui.enable;
      defaultText = lib.literalExpression "!config.services.overwitch.gui.enable";
      description = ''
        Whether to enable lingering for {option}`services.overwitch.user`, so its
        systemd instance, PipeWire and Overwitch start at boot without a login.
      '';
    };

    udev.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install the upstream udev rules and hwdb entries, which make
        Elektron USB devices accessible to all users.
      '';
    };

    settings = lib.mkOption {
      default = { };
      description = ''
        Contents of `~/.config/overwitch/preferences.json`, shared by the
        service and the GUI. Not managed when empty. Unset (null) options are
        omitted, leaving Overwitch's built-in defaults.
      '';
      example = lib.literalExpression ''
        {
          blocks = 12;
          timeout = 10;
          quality = 2;
          pipewireProps = "{ node.group = \"pro-audio-0\" }";
        }
      '';
      type = lib.types.submodule {
        freeformType = json.type;
        options = {
          blocks = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 2 32);
            default = null;
            description = "Blocks per USB transfer. Upstream default: 24.";
          };
          timeout = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.unsigned;
            default = null;
            description = "USB transfer timeout in milliseconds. Upstream default: 10.";
          };
          quality = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 0 4);
            default = null;
            description = "libsamplerate converter type, 0 (best) to 4 (fastest). Upstream default: 2.";
          };
          pipewireProps = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Value for `PIPEWIRE_PROPS` passed to the JACK clients.";
          };
        };
      };
    };

    enforceSettings = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.gui.enable;
      defaultText = lib.literalExpression "!config.services.overwitch.gui.enable";
      description = ''
        Whether the preferences file is a read-only link to the generated
        settings, replacing any existing file. When false, it is only written
        if absent, so that preferences changed in the GUI are kept.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.gui.enable || cfg.user != null;
            message = "services.overwitch.user must be set for headless operation (services.overwitch.gui.enable = false).";
          }
          {
            assertion = cfg.linger -> cfg.user != null;
            message = "services.overwitch.linger requires services.overwitch.user to be set.";
          }
          {
            assertion = cfg.user != null -> config.users.users ? ${cfg.user};
            message = "services.overwitch.user '${toString cfg.user}' is not a user declared in users.users.";
          }
        ];

        warnings = lib.optional (!usePipewireJack && !config.services.jack.jackd.enable) ''
          services.overwitch: neither services.pipewire.jack nor services.jack.jackd is enabled.
          Overwitch is a JACK client and needs a JACK server to connect to.
        '';

        environment.systemPackages = [ profilePackage ];

        services.udev.packages = lib.mkIf cfg.udev.enable [ cfg.package ];
        services.dbus.packages = [ dbusService ];

        # Under PipeWire, JACK clients obtain real time scheduling via RTKit.
        security.rtkit.enable = lib.mkIf usePipewireJack (lib.mkDefault true);

        systemd.user.services.overwitch = {
          description = "Overwitch service";
          after = lib.optional pipewire.enable "pipewire.service";
          requires = lib.optional pipewire.enable "pipewire.service";
          wantedBy = lib.optional cfg.autoStart "default.target";
          unitConfig.ConditionUser = lib.mkIf (cfg.user != null) cfg.user;
          # Binaries link against libjack2; point them at PipeWire's
          # implementation, as environment.sessionVariables does for logins.
          environment.LD_LIBRARY_PATH = lib.mkIf usePipewireJack "${pipewire.package.jack}/lib";
          serviceConfig = {
            Type = "notify-reload";
            ExecStart = lib.getExe' cfg.package "overwitch-service";
            Restart = "on-failure";
          };
        };

        users.users = lib.mkIf (cfg.linger && cfg.user != null) {
          ${cfg.user}.linger = true;
        };
      }

      (lib.mkIf (settings != { }) {
        systemd.user.tmpfiles.users = lib.mkIf (cfg.user != null) {
          ${cfg.user}.rules = tmpfilesRules;
        };
        systemd.user.tmpfiles.rules = lib.mkIf (cfg.user == null) tmpfilesRules;
      })
    ]
  );
}
