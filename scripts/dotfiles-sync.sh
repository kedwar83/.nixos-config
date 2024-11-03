#!/bin/bash
set -e

# Configuration
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME="/home/$ACTUAL_USER"
REPO_PATH="$ACTUAL_HOME/.dotfiles"
DOTFILES_PATH="$REPO_PATH"
CURRENT_USER=$(id -un $ACTUAL_USER)
TEMP_FILE=$(mktemp)
FAILURE_LOG="$DOTFILES_PATH/failure_log.txt"
SETUP_FLAG="$ACTUAL_HOME/.system_setup_complete"

echo "Running as user: $CURRENT_USER"
echo "Home directory: $ACTUAL_HOME"
echo "Repo and Dotfiles path: $REPO_PATH"
echo "Temporary file: $TEMP_FILE"
echo "Failure log file: $FAILURE_LOG"
# Exclusion list for rsync
EXCLUSIONS=(
    --exclude=".Xauthority"
    --exclude=".xsession-errors"
    --exclude=".bash_history"
    --exclude=".cache"
    --exclude=".compose-cache"
    --exclude=".local/share/Trash/"
    --exclude=".steam"
    --exclude=".vscode"
    --exclude="node_modules"
    --exclude=".nix-profile"
    --exclude=".nix-defexpr"
    --exclude=".dotfiles"
    --exclude=".mozilla/firefox/*/storage"
    --exclude=".mozilla/firefox/*/cache2"
    --exclude=".mozilla/firefox/*/crashes"
    --exclude=".mozilla/firefox/*/minidumps"
    --exclude=".mozilla/firefox/*/cookies.sqlite"
    --exclude=".mozilla/firefox/*/cookies.sqlite.bak"
    --exclude=".mozilla/firefox/*/cookies.sqlite-wal"
    --exclude=".mozilla/firefox/*/cookies.sqlite.bak-rebuild"
    --exclude=".mozilla/firefox/*/key4.db"
    --exclude=".mozilla/firefox/*/logins-backup.json"
    --exclude=".mozilla/firefox/*/lock"
    --exclude=".mozilla/firefox/*/sessionstore-backups"
    --exclude=".mozilla/firefox/*/logins.json"
    --exclude=".ssh"
    --exclude=".config/Joplin/SingletonCookie"
    --exclude=".config/Joplin/SingletonLock"
    --exclude=".config/Joplin/SingletonSocket"
    --exclude=".config/Joplin/GPUCache/"
    --exclude=".config/Signal\ Beta/stickers.noindex"
    --exclude=".config/Signal\ Beta/SingletonCookie"
    --exclude=".config/Signal\ Beta/SingletonLock"
    --exclude=".config/Signal\ Beta/SingletonSocket"
    --exclude=".local/state/nix/profiles/home-manager"
)
# Initialize/check git repository
init_git_repo() {
    echo "Checking git repository setup..." | tee -a "$TEMP_FILE"
    # Create directory if it doesn't exist
    if [ ! -d "$DOTFILES_PATH" ]; then
        sudo -u "$ACTUAL_USER" mkdir -p "$DOTFILES_PATH"
    fi

    # Initialize git if needed
    if [ ! -d "$DOTFILES_PATH/.git" ]; then
        echo "Initializing new git repository..." | tee -a "$TEMP_FILE"
        cd "$DOTFILES_PATH"
        sudo -u "$ACTUAL_USER" git init
        sudo -u "$ACTUAL_USER" git config --local init.defaultBranch main
    fi

    # Make sure it's a safe directory
    sudo -u "$ACTUAL_USER" git config --global --add safe.directory "$DOTFILES_PATH"

    # Check for remote
    if ! sudo -u "$ACTUAL_USER" git -C "$DOTFILES_PATH" remote get-url origin >/dev/null 2>&1; then
        echo "Setting up remote repository..." | tee -a "$TEMP_FILE"
        sudo -u "$ACTUAL_USER" git -C "$DOTFILES_PATH" remote add origin "git@github.com:$CURRENT_USER/.dotfiles.git"
    fi
}

# Copy dotfiles and their contents
copy_dotfiles() {
    echo "Copying dotfiles to repository..." | tee -a "$TEMP_FILE"
    # Use rsync to copy all dotfiles and their contents, excluding specified patterns
    sudo -u "$ACTUAL_USER" rsync -av --no-links "${EXCLUSIONS[@]}" \
        --include=".*" \
        --include=".*/**" \
        --exclude="*" \
        "$ACTUAL_HOME/" "$DOTFILES_PATH/"
}

# Main script execution
if [ ! -f "$SETUP_FLAG" ]; then
    echo "First-time setup detected..." | tee -a "$TEMP_FILE"
    sudo -u "$ACTUAL_USER" mkdir -p "$DOTFILES_PATH"
    init_git_repo
else
    init_git_repo
    copy_dotfiles
fi

# Stow all dotfiles
echo "Stowing dotfiles..." | tee -a "$TEMP_FILE"
if ! stow -vR --adopt . -d "$DOTFILES_PATH" -t "$ACTUAL_HOME" 2> >(tee -a "$FAILURE_LOG" >&2); then
    echo "Some files could not be stowed. Check the failure log for details." | tee -a "$TEMP_FILE"
    sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $ACTUAL_USER)/bus" notify-send "Stow Failure" "Some dotfiles could not be stowed. Check the failure log at: $FAILURE_LOG" --icon=dialog-error
fi

# Git operations
cd "$DOTFILES_PATH"

if ! sudo -u "$ACTUAL_USER" git diff --quiet || ! sudo -u "$ACTUAL_USER" git ls-files --others --exclude-standard --quiet; then
    echo "Changes detected, committing..." | tee -a "$TEMP_FILE"
    sudo -u "$ACTUAL_USER" git add .
    sudo -u "$ACTUAL_USER" git commit -m "Updated dotfiles: $(date '+%Y-%m-%d %H:%M:%S')"
    sudo -u "$ACTUAL_USER" git push -u origin main
else
    echo "No changes detected, skipping commit."
fi

echo "Log file available at: $TEMP_FILE"
echo "Failure log file available at: $FAILURE_LOG"
