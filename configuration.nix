{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  hostname = "nixos";
  username = "keganre";

  # Create executable script derivations
  mkScript = name: text: pkgs.writeShellScriptBin name text;

  # Define scripts with executable permissions
  dotfilesSyncScript = mkScript "dotfiles-sync" ''
    ${builtins.readFile ./scripts/dotfiles-sync.sh}
  '';

  nixosSyncScript = mkScript "nixos-sync" ''
    ${builtins.readFile ./scripts/nixos-sync.sh}
  '';

  serviceMonitorScript = mkScript "service-monitor" ''
    ${builtins.readFile ./scripts/service-monitor.sh}
  '';
in {
  networking = {
    hostName = hostname;
    networkmanager.enable = true;
    nameservers = ["1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one"];
  };

  imports = [
    ./hardware-configuration.nix
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services = {
    input-remapper.enable = true;
    avahi.enable = true;
    geoclue2.enable = true;
    blueman.enable = true;
    desktopManager.plasma6.enable = true;
    displayManager = {
      autoLogin = {
        enable = true;
        user = username;
      };
      defaultSession = "plasmax11";
    };
    xserver = {
      enable = true;
      displayManager = {
        lightdm.enable = true;
      };
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    printing.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = true;
    };
    ollama.enable = true;
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };
    resolved = {
      enable = true;
      dnssec = "true";
      domains = ["~."];
      fallbackDns = ["1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one"];
      dnsovertls = "true";
    };
  };

  systemd = {
    user.services.mpris-proxy = {
      description = "Mpris proxy";
      after = ["network.target" "sound.target"];
      wantedBy = ["default.target"];
      serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
    };
    services = {
      StartInputRemapperDaemonAtLogin = {
        enable = true;
        description = "Start input-remapper daemon after login";
        serviceConfig = {
          Type = "simple";
        };
        script = lib.getExe (pkgs.writeShellApplication {
          name = "start-input-mapper-daemon";
          runtimeInputs = with pkgs; [input-remapper procps su];
          text = ''
            until pgrep -u pierre; do
              sleep 1
            done
            sleep 2
            until [ $(pgrep -c -u root "input-remapper") -gt 1 ]; do
              input-remapper-service&
              sleep 1
              input-remapper-reader-service&
              sleep 1
            done
            su keganre -c "input-remapper-control --command stop-all"
            su keganre -c "input-remapper-control --command autoload"
            sleep infinity
          '';
        });
        wantedBy = ["default.target"];
      };

      ReloadInputRemapperAfterSleep = {
        enable = true;
        description = "Reload input-remapper config after sleep";
        after = ["suspend.target"];
        serviceConfig = {
          User = "pierre";
          Type = "forking";
        };
        script = lib.getExe (pkgs.writeShellApplication {
          name = "reload-input-mapper-config";
          runtimeInputs = with pkgs; [input-remapper ps gawk];
          text = ''
            input-remapper-control --command stop-all
            input-remapper-control --command autoload
            sleep 1
            until [[ $(ps aux | awk '$11~"input-remapper" && $12="<defunct>" {print $0}' | wc -l) -eq 0 ]]; do
              input-remapper-control --command stop-all
              input-remapper-control --command autoload
              sleep 1
            done
          '';
        });
        wantedBy = ["suspend.target"];
      };
      dotfiles-sync = {
        description = "Sync dotfiles to git repository";
        path = with pkgs; [
          bash
          git
          coreutils
          findutils
          libnotify
          rsync
          stow
          openssh
          util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${dotfilesSyncScript}/bin/dotfiles-sync";
          User = username;
          Group = "users";
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
        };
        environment = {
          GIT_SSH_COMMAND = "ssh -i /home/${username}/.ssh/id_ed25519";
          HOME = "/home/${username}";
        };
        wants = ["dbus.socket"];
        after = ["dbus.socket"];
      };

      service-monitor = {
        description = "Monitor critical services for failures";
        path = with pkgs; [
          bash
          systemd
          libnotify
          sudo
          coreutils
          gnugrep
          procps
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${serviceMonitorScript}/bin/service-monitor";
          User = username;
          Group = "users";
        };
        after = ["nixos-upgrade.service" "dotfiles-sync.service"];
      };
    };

    timers = {
      dotfiles-sync = {
        description = "Timer for dotfiles sync service";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "04:00:00";
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };

      service-monitor = {
        description = "Timer for service monitoring";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "04:00:00";
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };
    };
  };

  boot = {
    loader = {
      grub.enable = true;
      grub.device = "/dev/nvme0n1";
      grub.useOSProber = true;
      grub.enableCryptodisk = true;
    };
    initrd = {
      luks.devices = {
        "luks-e8a21db0-9d33-4155-b12e-d4aeb57b9bd0" = {
          device = "/dev/disk/by-uuid/e8a21db0-9d33-4155-b12e-d4aeb57b9bd0";
          keyFile = "/boot/crypto_keyfile.bin";
        };
        "luks-a0b27b0a-f8ac-4904-a1ad-b6aef0a82435" = {
          device = "/dev/disk/by-uuid/a0b27b0a-f8ac-4904-a1ad-b6aef0a82435";
          keyFile = "/boot/crypto_keyfile.bin";
        };
      };
      secrets = {
        "/boot/crypto_keyfile.bin" = null;
      };
    };
  };

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  security = {
    rtkit.enable = true;
    pam.services.login.enableKwallet = true;

    sudo.extraRules = [
      {
        users = [username];
        commands = [
          {
            command = "${nixosSyncScript}/bin/nixos-sync";
            options = ["PASSWD"];
          }
          {
            command = "${dotfilesSyncScript}/bin/dotfiles-sync";
            options = ["PASSWD"];
          }
          {
            command = "${serviceMonitorScript}/bin/service-monitor";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };

  time.timeZone = "America/New_York";
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = true;

  programs = {
    kdeconnect.enable = true;
    steam.enable = true;
  };

  xdg.mime.defaultApplications = {
    "text/html" = "firefox-nightly.desktop";
    "x-scheme-handler/http" = "firefox-nightly.desktop";
    "x-scheme-handler/https" = "firefox-nightly.desktop";
  };

  users.users.${username} = {
    isNormalUser = true;
    description = "Kegan Riley Edwards";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.kclock
    ];
  };

  # Home Manager configuration
  home-manager.backupFileExtension = "backup";
  home-manager.users.${username} = {pkgs, ...}: {
    home = {
      username = username;
      homeDirectory = "/home/${username}";
      stateVersion = "24.05";

      packages = with pkgs; [
        git
        alejandra
        inputs.firefox.packages.${pkgs.system}.firefox-nightly-bin
        signal-desktop-beta
        kdePackages.kdeplasma-addons
        ollama
        strawberry-qt6
        steam
        gimp-with-plugins
        vscodium
        gh
        libnotify
        input-remapper
        darkman
        joplin-desktop
        mullvad-vpn
        qbittorrent
        stow
        mpv
        neovim
        libgcc
      ];
    };

    services.darkman = {
      enable = true;
      settings = {
        usegeoclue = true;
      };

      darkModeScripts = {
        "kde-plasma.sh" = ''
          #!/bin/sh
          lookandfeeltool -platform offscreen --apply "org.kde.breezedark.desktop"
        '';

        "kde-konsole-theme.sh" = ''
          #!/usr/bin/env bash
          PROFILE='Breath'
          for pid in $(pidof konsole); do
            qdbus "org.kde.konsole-$pid" "/Windows/1" setDefaultProfile "$PROFILE"
            for session in $(qdbus "org.kde.konsole-$pid" /Windows/1 sessionList); do
              qdbus "org.kde.konsole-$pid" "/Sessions/$session" setProfile "$PROFILE"
            done
          done
        '';
      };

      lightModeScripts = {
        "kde-plasma.sh" = ''
          #!/bin/sh
          lookandfeeltool -platform offscreen --apply "org.kde.breeze.desktop"
        '';

        "kde-konsole-theme.sh" = ''
          #!/usr/bin/env bash
          PROFILE='Breath-light'
          for pid in $(pidof konsole); do
            qdbus "org.kde.konsole-$pid" "/Windows/1" setDefaultProfile "$PROFILE"
            for session in $(qdbus "org.kde.konsole-$pid" /Windows/1 sessionList); do
              qdbus "org.kde.konsole-$pid" "/Sessions/$session" setProfile "$PROFILE"
            done
          done
        '';
      };
    };

    programs = {
      home-manager.enable = true;
      git.enable = true;
    };
  };

  environment = {
    systemPackages = with pkgs; [
      # System scripts
      dotfilesSyncScript
      nixosSyncScript
      serviceMonitorScript

      # Development Tools
      gcc-unwrapped # Provides g++ binary
      gcc # GNU Compiler Collection
      gnumake
      binutils # Collection of binary tools
      glibc # GNU C Library
      glibc.dev # GNU C Library development files
      python3 # Python interpreter
      python3Packages.pip
      python3Packages.virtualenv
    ];
  };

  system = {
    autoUpgrade = {
      enable = true;
      flake = inputs.self.outPath;
      flags = ["--update-input" "nixpkgs" "-L"];
      dates = "02:00";
      randomizedDelaySec = "45min";
    };
    stateVersion = "24.05";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
