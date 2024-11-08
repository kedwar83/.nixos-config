#!/bin/bash

set -e

# Configuration
ACTUAL_HOME="$HOME"
REPO_PATH="$ACTUAL_HOME/.dotfiles"
DOTFILES_PATH="$REPO_PATH"
TEMP_FILE=$(mktemp)
FAILURE_LOG="$DOTFILES_PATH/failure_log.txt"
SETUP_FLAG="$ACTUAL_HOME/.system_setup_complete"

echo "Running as user: $USER"
echo "Home directory: $ACTUAL_HOME"
echo "Repo and Dotfiles path: $REPO_PATH"
echo "Temporary file: $TEMP_FILE"
echo "Failure log file: $FAILURE_LOG"

# Exclusion list for rsync
EXCLUSIONS=(
    # System and general security files
    --exclude=".Xauthority"
    --exclude=".xsession-errors"
    --exclude=".bash_history"
    --exclude=".ssh"
    --exclude=".gnupg"
    --exclude=".pki"

    # General cache and temporary files
    --exclude=".cache"
    --exclude=".compose-cache"
    --exclude=".local/share/Trash/"
    --exclude="*/recently-used.xbel"

    # Development and build files
    --exclude=".steam"
    --exclude=".vscode"
    --exclude="node_modules"

    # Nix-specific
    --exclude=".nix-profile"
    --exclude=".nix-defexpr"
    --exclude=".dotfiles"
    --exclude=".local/state/nix/profiles/home-manager"
    --exclude=".nixos-config"
    --exclude=".system_setup_complete"

    # Firefox profile data
    --exclude=".mozilla/firefox/*/storage"
    --exclude=".mozilla/firefox/*/cache2"
    --exclude=".mozilla/firefox/*/crashes"
    --exclude=".mozilla/firefox/*/minidumps"
    # Cookie data (exclude) but not settings
    --exclude=".mozilla/firefox/*/cookies.sqlite"
    --exclude=".mozilla/firefox/*/cookies.sqlite.bak"
    --exclude=".mozilla/firefox/*/cookies.sqlite-wal"
    --exclude=".mozilla/firefox/*/cookies.sqlite-shm"
    --exclude=".mozilla/firefox/*/cookies.sqlite.bak-rebuild"
    # Security-sensitive data
    --exclude=".mozilla/firefox/*/key4.db"
    --exclude=".mozilla/firefox/*/logins-backup.json"
    --exclude=".mozilla/firefox/*/lock"
    --exclude=".mozilla/firefox/*/sessionstore-backups"
    --exclude=".mozilla/firefox/*/logins.json"
    --exclude=".mozilla/firefox/*/Login\ Data"
    --exclude=".mozilla/firefox/*/Login\ Data-journal"
    --exclude=".mozilla/firefox/*/Web\ Data"
    --exclude=".mozilla/firefox/*/Web\ Data-journal"
    --exclude=".mozilla/firefox/*/Local\ Storage"
    --exclude=".mozilla/firefox/*/Service\ Worker"
    --exclude=".mozilla/firefox/*/Network"
    --exclude=".mozilla/firefox/*/GPUCache"
    --exclude=".mozilla/firefox/*/sessionstore*"
    --exclude=".mozilla/firefox/*/session*"
    --exclude=".mozilla/firefox/*/formhistory.sqlite"
    --exclude=".mozilla/firefox/*/autofill*"
    --exclude=".mozilla/firefox/*/places.sqlite*"
    --exclude=".mozilla/firefox/*/favicons.sqlite*"
    --exclude=".mozilla/firefox/*/cert*.db"
    --exclude=".mozilla/firefox/*/webappsstore.sqlite*"
    --exclude=".mozilla/firefox/*/saved-telemetry-pings"
    # Note: permissions.sqlite removed to keep cookie settings

    # Brave Browser data
    # Cookie data (exclude) but not settings
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Cookies"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Cookies-journal"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Extension\ Cookies"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Extension\ Cookies-journal"
    # Note: Preferences file not excluded to keep cookie settings
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Login\ Data"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Login\ Data-journal"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Web\ Data"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Web\ Data-journal"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/*.log"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Sessions"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Local\ Storage"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Service\ Worker"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Cache"
    --exclude=".config/BraveSoftware/Brave-Browser/Safe\ Browsing"
    --exclude=".config/BraveSoftware/Brave-Browser/CertificateRevocation"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/GPUCache"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Network"
    --exclude=".config/BraveSoftware/Brave-Browser/Crash\ Reports"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Storage/ext"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/AutofillStrikeDatabase"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/History*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Favicons*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Origin\ Bound\ Certs*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Sync\ Data*"
    # Extension data (exclude) but not settings
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Extension\ State"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Extension\ Scripts"
    # Note: Extension Rules not excluded to keep settings
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Shortcuts*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Top\ Sites*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Visit*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Heavy\ Ad\ Intervention*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Media\ History*"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/Platform\ Notifications"

    # Joplin
    --exclude=".config/Joplin/SingletonCookie"
    --exclude=".config/Joplin/SingletonLock"
    --exclude=".config/Joplin/SingletonSocket"
    --exclude=".config/Joplin/GPUCache/"
    --exclude=".config/Joplin/Local\ Storage/leveldb"
    --exclude=".config/Joplin/databases"
    --exclude=".config/Joplin/security"
    --exclude=".config/Joplin/tmp"
    --exclude=".config/Joplin/*.log"
    --exclude=".config/Joplin/resources"

    # Signal
    --exclude=".config/Signal\ Beta/stickers.noindex"
    --exclude=".config/Signal\ Beta/SingletonCookie"
    --exclude=".config/Signal\ Beta/SingletonLock"
    --exclude=".config/Signal\ Beta/SingletonSocket"
    --exclude=".config/Signal\ Beta/databases"
    --exclude=".config/Signal\ Beta/sql"
    --exclude=".config/Signal\ Beta/logs"
    --exclude=".config/Signal\ Beta/attachments"
    --exclude=".config/Signal\ Beta/config.json"
    --exclude=".config/Signal\ Beta/debug.log"
    --exclude=".config/Signal\ Beta/GPUCache"
    --exclude=".config/Signal\ Beta/IndexedDB"
    --exclude=".config/Signal\ Beta/Local\ Storage"
    --exclude=".config/Signal\ Beta/Session\ Storage"
    --exclude=".config/BraveSoftware/Brave-Browser/Default/IndexedDB"
)

# Initialize/check git repository
init_git_repo() {
    echo "Checking git repository setup..." | tee -a "$TEMP_FILE"

    # Create directory if it doesn't exist
    if [ ! -d "$DOTFILES_PATH" ]; then
        echo "Creating dotfiles directory..." | tee -a "$TEMP_FILE"
        mkdir -p "$DOTFILES_PATH"
    fi

    # Change to the dotfiles directory
    cd "$DOTFILES_PATH"

    # Initialize git if needed
    if [ ! -d "$DOTFILES_PATH/.git" ]; then
        echo "Initializing new git repository..." | tee -a "$TEMP_FILE"
        git init
        # Make sure it's a safe directory right after initialization
        git config --global --add safe.directory "$DOTFILES_PATH"
        # Create main branch and set it as default
        git checkout -b main
    else
        # Make sure it's a safe directory
        git config --global --add safe.directory "$DOTFILES_PATH"
    fi

    # Check for remote only if we have a git repository
    if [ -d "$DOTFILES_PATH/.git" ]; then
        if ! git remote get-url origin >/dev/null 2>&1; then
            echo "Setting up remote repository..." | tee -a "$TEMP_FILE"
            git remote add origin "git@github.com:kedwar83/.dotfiles.git"
        fi

        # Try to fetch only if we have a remote configured
        if git remote -v | grep -q origin; then
            echo "Fetching from remote..." | tee -a "$TEMP_FILE"
            git fetch origin || true
        fi

        # Ensure we're on the main branch
        if ! git rev-parse --verify main >/dev/null 2>&1; then
            echo "Creating main branch..." | tee -a "$TEMP_FILE"
            git checkout -b main
        else
            echo "Checking out main branch..." | tee -a "$TEMP_FILE"
            git checkout main || git checkout -b main
        fi
    fi
}

copy_dotfiles() {
    echo "Copying dotfiles to repository..." | tee -a "$TEMP_FILE"
    rsync -av --no-links "${EXCLUSIONS[@]}" \
        --include=".*" \
        --include=".*/**" \
        --exclude="*" \
        "$ACTUAL_HOME/" "$DOTFILES_PATH/"
}

# Main script execution
if [ ! -f "$SETUP_FLAG" ]; then
    echo "First-time setup detected..." | tee -a "$TEMP_FILE"
    mkdir -p "$DOTFILES_PATH"
    init_git_repo
else
    init_git_repo
    copy_dotfiles
fi

# Stow all dotfiles
echo "Stowing dotfiles..." | tee -a "$TEMP_FILE"
if ! stow -vR --adopt . -d "$DOTFILES_PATH" -t "$ACTUAL_HOME" 2> >(tee -a "$FAILURE_LOG" >&2); then
    echo "Some files could not be stowed. Check the failure log for details." | tee -a "$TEMP_FILE"
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" notify-send "Stow Failure" "Some dotfiles could not be stowed. Check the failure log at: $FAILURE_LOG" --icon=dialog-error
fi

# Git operations
cd "$DOTFILES_PATH"

if ! git diff --quiet || ! git ls-files --others --exclude-standard --quiet; then
    echo "Changes detected, committing..." | tee -a "$TEMP_FILE"
    git add .
    git commit -m "Updated dotfiles: $(date '+%Y-%m-%d %H:%M:%S')"
    git push -u origin main
else
    echo "No changes detected, skipping commit."
fi

echo "Log file available at: $TEMP_FILE"
echo "Failure log file available at: $FAILURE_LOG"
