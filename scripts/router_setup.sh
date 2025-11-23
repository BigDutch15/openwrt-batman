#!/bin/ash

# Turn an OpenWrt dumb access point into a Wi-fi mesh point

# use at your own risk !!!!
# backup your router first !!!!
# script expects factory settings+1st script to be executed!!!!
# the script might not run on all hardware !!!

# ====================================================================
# STEP 1: Detect WAN interface for firewall configuration
# ====================================================================
echo "[INFO] Detecting WAN interface for firewall rules..."
. /lib/functions/network.sh
network_flush_cache
network_find_wan NET_IF
FW_WAN="$(fw4 -q network ${NET_IF})"
echo "[INFO] WAN interface detected: $NET_IF (firewall zone: $FW_WAN)"