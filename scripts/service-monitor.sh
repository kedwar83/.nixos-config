#!/usr/bin/env bash

# Function to send desktop notification
send_notification() {
    local service=$1
    local status=$2
    
    # Get list of active display users
    for userid in $(w -hs | cut -d' ' -f1 | sort -u); do
        # Get user's DBus session address
        user_runtime_dir="/run/user/$(id -u $userid)"
        if [ -d "$user_runtime_dir" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=$user_runtime_dir/bus"
            # Send notification as the user
            sudo -u $userid DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
                notify-send -u critical "Service Failure" "The $service service has failed: $status"
        fi
    done
}

# Check system auto-upgrade service
check_auto_upgrade() {
    # Get the last auto-upgrade journal entries
    if journalctl -u nixos-upgrade.service -n 50 --no-pager | grep -q "error\|failed\|failure"; then
        send_notification "system auto-upgrade" "Check system logs for details"
    fi
}

# Check dotfiles sync service
check_dotfiles_sync() {
    # Get the last dotfiles-sync journal entries
    if journalctl -u dotfiles-sync.service -n 50 --no-pager | grep -q "error\|failed\|failure"; then
        send_notification "dotfiles sync" "Check system logs for details"
    fi
}

# Run checks
check_auto_upgrade
check_dotfiles_sync
