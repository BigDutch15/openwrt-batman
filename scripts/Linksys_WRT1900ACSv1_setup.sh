#!/bin/ash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/common_functions.sh"

REQUIRED_HARDWARE="Linksys WRT1900ACS v1"

# Load configuration
router_name=${ROUTER_NAME:-"Linksys_WRT1900ACSv1"}
router_timezone=${ROUTER_TIMEZONE:-"CST6CDT,M3.2.0,M11.1.0"}
router_timezone_name=${ROUTER_TIMEZONE_NAME:-"America/Chicago"}

mobility_domain=${MOBILITY_DOMAIN:-"11df"}

guest_net_id=${GUEST_NET_ID:-"guest"}
guest_ipaddr=${GUEST_IPADDR:-"192.168.3.1"}
guest_ssid=${GUEST_SSID:-"Guest"}
guest_pwd=${GUEST_PWD:-"CHANGE-ME-INSECURE-DEFAULT"}
guest_channel=${GUEST_CHANNEL:-"1"}
guest_wifi_device=${GUEST_WIFI_DEVICE:-"radio1"}

echo "[INFO] Router Name: $router_name"
echo "[INFO] Router Timezone: $router_timezone"
echo "[INFO] Router Timezone Name: $router_timezone_name"
echo "[INFO] Mobility Domain: $mobility_domain"
echo "[INFO] Guest Net ID: $guest_net_id"
echo "[INFO] Guest IP Address: $guest_ipaddr"
echo "[INFO] Guest SSID: $guest_ssid"
echo "[INFO] Guest Password: [REDACTED]"
echo "[INFO] Guest Channel: $guest_channel"
echo "[INFO] Guest WiFi Device: $guest_wifi_device"

iot_net_id=${IOT_NET_ID:-"iot"}
iot_ipaddr=${IOT_IPADDR:-"192.168.4.1"}
iot_ssid=${IOT_SSID:-"IoT"}
iot_pwd=${IOT_PWD:-"CHANGE-ME-INSECURE-DEFAULT"}
iot_channel=${IOT_CHANNEL:-"1"}
iot_wifi_device=${IOT_WIFI_DEVICE:-"radio1"}

echo "[INFO] IoT Net ID: $iot_net_id"
echo "[INFO] IoT IP Address: $iot_ipaddr"
echo "[INFO] IoT SSID: $iot_ssid"
echo "[INFO] IoT Password: [REDACTED]"
echo "[INFO] IoT Channel: $iot_channel"
echo "[INFO] IoT WiFi Device: $iot_wifi_device"

home_net_id=${HOME_NET_ID:-"home"}
home_ipaddr=${HOME_IPADDR:-"192.168.5.1"}
home_ssid=${HOME_SSID:-"Home"}
home_pwd=${HOME_PWD:-"CHANGE-ME-INSECURE-DEFAULT"}
home_channel=${HOME_CHANNEL:-"36"}
home_wifi_device=${HOME_WIFI_DEVICE:-"radio0"}

echo "[INFO] Home Net ID: $home_net_id"
echo "[INFO] Home IP Address: $home_ipaddr"
echo "[INFO] Home SSID: $home_ssid"
echo "[INFO] Home Password: [REDACTED]"
echo "[INFO] Home Channel: $home_channel"
echo "[INFO] Home WiFi Device: $home_wifi_device"

# ====================================================================
# STEP 0: Validate hardware
# ====================================================================
if ! validate_hardware "$REQUIRED_HARDWARE"; then
    exit 1
fi


# ====================================================================
# STEP 1: Detect WAN interface for firewall configuration
# ====================================================================
detect_wan_interface

# ====================================================================
# STEP 2: Install additional software packages
# ====================================================================
if ! install_mesh_packages; then
    exit 1
fi


# ====================================================================
# STEP 3: Set system information
# ====================================================================
if ! set_hostname "$router_name"; then
    exit 1
fi

if ! set_timezone "$router_timezone_name" "$router_timezone"; then
    exit 1
fi

# ====================================================================
# STEP 4: Create the guest network interface
# ====================================================================
echo "[INFO] Creating guest network..."
create_network "$guest_net_id" "$guest_ipaddr" "$guest_ssid" "$guest_pwd" "$guest_channel" "$guest_wifi_device" "$mobility_domain" "$FW_WAN" 1 0

# ====================================================================
# STEP 5: Create the IoT network interface
# ====================================================================
echo "[INFO] Creating IoT network..."
create_network "$iot_net_id" "$iot_ipaddr" "$iot_ssid" "$iot_pwd" "$iot_channel" "$iot_wifi_device" "$mobility_domain" "$FW_WAN" 1 0

# ====================================================================
# STEP 6: Create the Home network interface
# ====================================================================
echo "[INFO] Creating Home network..."
create_network "$home_net_id" "$home_ipaddr" "$home_ssid" "$home_pwd" "$home_channel" "$home_wifi_device" "$mobility_domain" "$FW_WAN" 0 1

# ====================================================================
# STEP 7: Delete OpenWrt default radios
# ====================================================================
delete_default_radios radio0 radio1

# ====================================================================
# STEP 8: Apply configuration changes
# ====================================================================
if ! restart_services; then
    exit 1
fi
