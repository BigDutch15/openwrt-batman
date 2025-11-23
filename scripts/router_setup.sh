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


echo "[INFO] Setting system hostname to $ROUTER_NAME..."

