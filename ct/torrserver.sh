#!/usr/bin/env bash
# ProxmoxVE Community Script Style
# TorrServer LXC installer
# Author: Oleg Tukachev
# License: MIT

set -e

# --- Default Values ---
DEFAULT_HOSTNAME="torrserver"
DEFAULT_STORAGE="local-lvm"
DEFAULT_DISK_SIZE="8G"
DEFAULT_CORE_COUNT="2"
DEFAULT_RAM_SIZE="512"
DEFAULT_BRIDGE="vmbr0"
NEXTID=$(pvesh get /cluster/nextid)

echo "======================================================="
echo "   TorrServer Installer for Proxmox LXC"
echo "======================================================="

# --- Interactive Configuration Block ---
read -p "Use default settings? (Y/n): " use_defaults
use_defaults=${use_defaults:-"y"}

if [[ $use_defaults =~ ^[Nn]$ ]]; then
    echo "--- Manual Configuration ---"
    read -p "Container ID [$NEXTID]: " CTID
    CTID=${CTID:-$NEXTID}

    read -p "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

    read -p "Storage pool [$DEFAULT_STORAGE]: " STORAGE
    STORAGE=${STORAGE:-$DEFAULT_STORAGE}

    read -p "Disk size [$DEFAULT_DISK_SIZE]: " DISK_SIZE
    DISK_SIZE=${DISK_SIZE:-$DEFAULT_DISK_SIZE}

    read -p "CPU core count [$DEFAULT_CORE_COUNT]: " CORE_COUNT
    CORE_COUNT=${CORE_COUNT:-$DEFAULT_CORE_COUNT}

    read -p "RAM size in MB [$DEFAULT_RAM_SIZE]: " RAM_SIZE
    RAM_SIZE=${RAM_SIZE:-$DEFAULT_RAM_SIZE}

    read -p "Network bridge [$DEFAULT_BRIDGE]: " BRIDGE
    BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}
else
    echo "Using default configuration..."
    CTID=$NEXTID
    HOSTNAME=$DEFAULT_HOSTNAME
    STORAGE=$DEFAULT_STORAGE
    DISK_SIZE=$DEFAULT_DISK_SIZE
    CORE_COUNT=$DEFAULT_CORE_COUNT
    RAM_SIZE=$DEFAULT_RAM_SIZE
    BRIDGE=$DEFAULT_BRIDGE
fi

echo "-------------------------------------------------------"
echo "Target Config: ID:$CTID, Name:$HOSTNAME, Storage:$STORAGE, Disk:$DISK_SIZE"
echo "-------------------------------------------------------"

# --- Template Search Logic ---
echo "Updating Proxmox template database..."
pveam update > /dev/null

# Dynamically find the latest Debian 12 Standard template
TEMPLATE=$(pveam available --section system | grep "debian-12-standard" | awk '{print $2}' | sort -V | tail -n 1)

if [ -z "$TEMPLATE" ]; then
    echo "Error: Debian 12 template not found in Proxmox repositories."
    exit 1
fi

# Check if template is already downloaded, if not - download it
if ! pveam list local | grep -q "$TEMPLATE"; then
    echo "Downloading template: $TEMPLATE..."
    pveam download local "$TEMPLATE"
fi

# --- Container Creation ---
echo "Creating LXC container $CTID..."
pct create $CTID local:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
    --storage $STORAGE \
    --rootfs $STORAGE:$DISK_SIZE \
    --cores $CORE_COUNT \
    --memory $RAM_SIZE \
    --swap 512 \
    --unprivileged 1 \
    --features nesting=1 \
    --ostype debian \
    --start 1

echo "Waiting for network to initialize (5s)..."
sleep 5

# --- TorrServer Installation ---
echo "Installing dependencies and TorrServer inside the container..."
pct exec $CTID -- bash -c "apt-get update && apt-get install -y curl wget"
pct exec $CTID -- bash -c "curl -sL https://raw.githubusercontent.com/YouROK/TorrServer/master/installTorrServerLinux.sh | bash"

# Fetch the container's IP address
CT_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo "======================================================="
echo "Installation completed successfully!"
echo "TorrServer Web UI: http://$CT_IP:8090"
echo "Quick commands: pct start $CTID | pct stop $CTID | pct enter $CTID"
echo "======================================================="
