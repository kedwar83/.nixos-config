#!/usr/bin/env bash
set -e

ACTUAL_USER=${SUDO_USER:-$USER}
NIXOS_CONFIG_DIR="/etc/nixos"
NIXOS_DOT_DIR="/home/$ACTUAL_USER/.nixos-config"
CURRENT_USER=$(id -un $ACTUAL_USER)
SETUP_FLAG="/home/$ACTUAL_USER/.system_setup_complete"
GIT_REPO_URL="git@github.com:kedwar83/.nixos-config.git"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

echo "Running as user: $CURRENT_USER"
echo "NixOS config directory: $NIXOS_CONFIG_DIR"
echo "NixOS dot directory: $NIXOS_DOT_DIR"
echo "Git repository URL: $GIT_REPO_URL"

# Setup git config as the regular user
if [ ! -d "$NIXOS_DOT_DIR/.git" ]; then
    echo 'Initializing a new git repository in $NIXOS_DOT_DIR...'
    sudo -u $ACTUAL_USER git init "$NIXOS_DOT_DIR"
fi

if [ -z "$(sudo -u $ACTUAL_USER git config --global user.email)" ]; then
    echo 'Setting git email...'
    sudo -u $ACTUAL_USER git config --global user.email 'keganedwards@proton.me'
fi

if ! sudo -u $ACTUAL_USER git config --global --get safe.directory | grep -q "^$NIXOS_DOT_DIR$"; then
    echo "Adding $NIXOS_DOT_DIR as a safe directory..."
    sudo -u $ACTUAL_USER git config --global --add safe.directory "$NIXOS_DOT_DIR"
fi

if ! sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" remote get-url origin &> /dev/null; then
    echo 'No remote repository found. Adding origin remote...'
    sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" remote add origin "$GIT_REPO_URL"
else
    echo 'Remote repository already configured.'
fi

generate_luks_config() {
    local config_file="$NIXOS_DOT_DIR/configuration.nix"
    local temp_file=$(mktemp)
    local boot_device=$(findmnt -n -o SOURCE /boot | grep -o '/dev/nvme[0-9]n[0-9]')
    local luks_uuids=($(blkid | grep "TYPE=\"crypto_LUKS\"" | grep -o "UUID=\"[^\"]*\"" | cut -d'"' -f2))

    cat > "$temp_file" << EOL
  boot = {
    loader = {
      grub.enable = true;
      grub.device = "${boot_device}";
      grub.useOSProber = true;
      grub.enableCryptodisk = true;
    };
    initrd = {
      luks.devices = {
EOL

    for uuid in "${luks_uuids[@]}"; do
        cat >> "$temp_file" << EOL
        "luks-${uuid}" = {
          device = "/dev/disk/by-uuid/${uuid}";
          keyFile = "/boot/crypto_keyfile.bin";
        };
EOL
    done

    cat >> "$temp_file" << EOL
      };
      secrets = {
        "/boot/crypto_keyfile.bin" = null;
      };
    };
  };
EOL

    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.backup"
        awk -v replacement="$(cat $temp_file)" '
        /^[[:space:]]*boot[[:space:]]*=[[:space:]]*{/ {
            print replacement
            in_boot_section=1
            next
        }
        in_boot_section {
            if (match($0, /^[[:space:]]*};[[:space:]]*$/)) {
                in_boot_section=0
                next
            }
            if (in_boot_section) next
        }
        {print}
        ' "${config_file}.backup" > "$config_file"

        rm "$temp_file"
        echo "LUKS configuration updated successfully."
    else
        echo "Error: configuration.nix not found in $NIXOS_DOT_DIR"
        rm "$temp_file"
        return 1
    fi
}

# In the first-time setup section
if [ ! -f "$SETUP_FLAG" ]; then
    echo "First-time setup detected..."
    echo "Generating LUKS configuration..."
    generate_luks_config

    echo "Copying configuration to /etc/nixos..."
    rsync -av --exclude='.git' --exclude='.gitignore' "$NIXOS_DOT_DIR/" "$NIXOS_CONFIG_DIR/"
    chown -R root $NIXOS_CONFIG_DIR

    echo "NixOS Rebuilding..."
    nixos-rebuild switch --flake /etc/nixos#nixos

    echo "Running dotfiles sync as user..."
    sudo -u $ACTUAL_USER dotfiles-sync

    touch "$SETUP_FLAG"
else
    echo "Regular sync detected..."

    # Change to the user's dot directory and setup git config as the actual user
    # The setup_git_config logic has been inlined above

    # Formatting Nix files with Alejandra
    echo 'Formatting Nix files with Alejandra...'
    alejandra "$NIXOS_CONFIG_DIR"

    # Copying NixOS configuration to the dot directory
    echo 'Copying NixOS configuration to dot directory...'
    rsync -av --exclude='hardware-configuration.nix' "$NIXOS_CONFIG_DIR/" "$NIXOS_DOT_DIR/"
    chown -R $CURRENT_USER $NIXOS_DOT_DIR

    # Adding changes to git
    sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" add .

    # Check for changes in the repository
    if ! sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" diff --quiet || ! sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" diff --cached --quiet; then
        echo 'Changes detected, proceeding with rebuild and commit...'

        # NixOS rebuilding
        echo 'NixOS Rebuilding...'
        nixos-rebuild switch --flake /etc/nixos#nixos &> /tmp/nixos-switch.log || (cat /tmp/nixos-switch.log | grep --color error && exit 1)

        # Get the current NixOS generation again
        current=$(nixos-rebuild list-generations | grep current)

        # Commit changes
        sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" commit -m "$current"

        # Fetch origin and check out the main branch
        sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" fetch origin
        if ! sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" rev-parse --verify main; then
            echo 'Branch main does not exist. Creating it...'
            sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" checkout -b main
        else
            echo 'Checking out main branch...'
            sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" checkout main
        fi

        # Push changes to origin
        sudo -u $ACTUAL_USER git -C "$NIXOS_DOT_DIR" push origin main

        # Notify user
        sudo -u $ACTUAL_USER DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY notify-send 'NixOS Rebuilt OK!' --icon=software-update-available

    else
        echo 'No changes detected, skipping rebuild and commit.'
    fi
fi
