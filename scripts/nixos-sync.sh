#!/usr/bin/env bash
set -e

ACTUAL_USER=${SUDO_USER:-$USER}
NIXOS_CONFIG_DIR="/etc/nixos"
NIXOS_DOT_DIR="/home/$ACTUAL_USER/.nixos-config"
CURRENT_USER=$(id -un $ACTUAL_USER)
SETUP_FLAG="/home/$ACTUAL_USER/.system_setup_complete"
GIT_REPO_URL="git@github.com:kedwar83/.nixos-config.git"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a normal user, not as root"
    exit 1
fi

echo "Running as user: $CURRENT_USER"
echo "NixOS config directory: $NIXOS_CONFIG_DIR"
echo "NixOS dot directory: $NIXOS_DOT_DIR"
echo "Git repository URL: $GIT_REPO_URL"

# Function to setup git config
setup_git_config() {
    # Check if the .git directory exists
    if [ ! -d "$NIXOS_DOT_DIR/.git" ]; then
        echo "Initializing a new git repository in $NIXOS_DOT_DIR..."
        git init "$NIXOS_DOT_DIR"
    fi

    # Check if git email is set
    if [ -z "$(git config --global user.email)" ]; then
        echo "Setting git email..."
        git config --global user.email "keganedwards@proton.me"
    fi

    # Check if safe.directory is set
    if ! git config --global --get safe.directory | grep -q "^$NIXOS_DOT_DIR\$"; then
        echo "Adding $NIXOS_DOT_DIR as a safe directory..."
        git config --global --add safe.directory "$NIXOS_DOT_DIR"
    fi

    # Check if a remote repository is set
    if ! git -C "$NIXOS_DOT_DIR" remote get-url origin &> /dev/null; then
        echo "No remote repository found. Adding origin remote..."
        git -C "$NIXOS_DOT_DIR" remote add origin "$GIT_REPO_URL"
    else
        echo "Remote repository already configured."
    fi
}

generate_luks_config() {
    local config_file="$NIXOS_DOT_DIR/configuration.nix"
    local temp_file=$(mktemp)

    # Find the boot device (assuming it's an NVMe drive)
    local boot_device=$(sudo findmnt -n -o SOURCE /boot | grep -o '/dev/nvme[0-9]n[0-9]')

    # Get LUKS device UUIDs
    local luks_uuids=($(sudo blkid | grep "TYPE=\"crypto_LUKS\"" | grep -o "UUID=\"[^\"]*\"" | cut -d'"' -f2))

    # Generate the boot configuration section
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

    # Add each LUKS device to the configuration
    for uuid in "${luks_uuids[@]}"; do
        cat >> "$temp_file" << EOL
        "luks-${uuid}" = {
          device = "/dev/disk/by-uuid/${uuid}";
          keyFile = "/boot/crypto_keyfile.bin";
        };
EOL
    done

    # Close the configuration section
    cat >> "$temp_file" << EOL
      };
      secrets = {
        "/boot/crypto_keyfile.bin" = null;
      };
    };
  };
EOL

    # Replace the boot configuration section in the original file
    if [ -f "$config_file" ]; then
        # Create a backup
        cp "$config_file" "${config_file}.backup"

        # Replace the boot configuration section
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

        # Clean up
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
    # Generate LUKS configuration
    echo "Generating LUKS configuration..."
    generate_luks_config

    # Copy all files except .git and .gitignore to /etc/nixos
    echo "Copying configuration to /etc/nixos..."
    sudo rsync -av --exclude='.git' --exclude='.gitignore' "$NIXOS_DOT_DIR/" "$NIXOS_CONFIG_DIR/"

    echo "NixOS Rebuilding..."
    sudo nixos-rebuild switch --flake /etc/nixos#nixos

    # Run dotfiles sync
    echo "Running dotfiles sync..."
    dotfiles-sync

    # Create setup flag
    touch "$SETUP_FLAG"
else
    # Regular sync
    echo "Regular sync detected..."

    cd "$NIXOS_DOT_DIR"
    setup_git_config

    # Copy current NixOS config to dot directory
    echo "Copying NixOS configuration to dot directory..."
    sudo rsync -av --exclude='hardware-configuration.nix' "$NIXOS_CONFIG_DIR/" "$NIXOS_DOT_DIR/"

    git add .

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Changes detected, proceeding with formatting, rebuild and commit..."

        # Format all Nix files using Alejandra
        echo "Formatting Nix files with Alejandra..."
        sudo alejandra "$NIXOS_CONFIG_DIR"

        echo "NixOS Rebuilding..."
        sudo nixos-rebuild switch --flake /etc/nixos#nixos &> nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
        current=$(nixos-rebuild list-generations | grep current)

        git commit -m "$current"

        # Ensure we're on the main branch or create it if it doesn't exist
        git fetch origin
        if ! git rev-parse --verify main; then
            echo "Branch 'main' does not exist. Creating it..."
            git checkout -b main
        else
            echo "Checking out main branch..."
            git checkout main
        fi

        # Push changes to the main branch
        git push origin main

        # Notify of successful rebuild
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" notify-send "NixOS Rebuilt OK!" --icon=software-update-available
    else
        echo "No changes detected, skipping rebuild and commit."
    fi
fi
