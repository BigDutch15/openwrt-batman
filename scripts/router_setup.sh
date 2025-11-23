#!/bin/ash


ROUTER_NAME=$ROUTER_NAME || "OpenWrt"


# ====================================================================
# STEP 1: Detect WAN interface for firewall configuration
# ====================================================================
echo "[INFO] Detecting WAN interface for firewall rules..."
. /lib/functions/network.sh
network_flush_cache
network_find_wan NET_IF
FW_WAN="$(fw4 -q network ${NET_IF})"
echo "[INFO] WAN interface detected: $NET_IF (firewall zone: $FW_WAN)"

# ====================================================================
# STEP 2: Install additional software packages
# ====================================================================
echo "[INFO] Checking and removing wpad-basic-mbedtls package..."
if opkg list-installed | grep wpad-basic-mbedtls > /dev/null; then
    echo "[INFO] Removing wpad-basic-mbedtls (incompatible with mesh)"
    opkg remove wpad-basic-mbedtls
    echo "[SUCCESS] wpad-basic-mbedtls removed"
fi

echo "[INFO] Checking and removing wpad-basic-wolfssl package..."
if opkg list-installed | grep wpad-basic-wolfssl > /dev/null; then
    echo "[INFO] Removing wpad-basic-wolfssl (incompatible with mesh)"
    opkg remove wpad-basic-wolfssl
    echo "[SUCCESS] wpad-basic-wolfssl removed"
fi

echo "[INFO] Checking and installing wpad-mesh-openssl package..."
if opkg list-installed | grep wpad-mesh-openssl > /dev/null; then
    echo "[INFO] wpad-mesh-openssl is already installed"
else
    echo "[INFO] Installing wpad-mesh-openssl..."
    opkg update
    opkg install wpad-mesh-openssl
    echo "[SUCCESS] wpad-mesh-openssl installed"
fi

echo "[INFO] Checking and installing kmod-batman-adv package..."
if opkg list-installed | grep kmod-batman-adv > /dev/null; then
    echo "[INFO] kmod-batman-adv is already installed"
else
    echo "[INFO] Installing kmod-batman-adv..."
    opkg update
    opkg install kmod-batman-adv
    echo "[SUCCESS] kmod-batman-adv installed"
fi



echo "[INFO] Setting system hostname to $ROUTER_NAME..."

