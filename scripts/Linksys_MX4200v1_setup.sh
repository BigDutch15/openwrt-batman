#!/bin/ash

REQUIRED_HARDWARE="Linksys MX4200v1"

# Load configuration
router_name=${ROUTER_NAME:-"OpenWrt"}
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

# Function to get machine model from dmesg
get_machine_model() {
	local model=""
	
	# Try to extract machine model from dmesg output
	# Look for common patterns like "Machine model:" or "Machine:"
	model=$(dmesg | grep -i "machine" | grep -i "model" | head -n 1 | sed 's/.*[Mm]achine.*[Mm]odel[: ]*//; s/^[ \t]*//')
	
	# If that didn't work, try alternative patterns
	if [ -z "$model" ]; then
		model=$(dmesg | grep -E "^[[:space:]]*Machine:" | head -n 1 | sed 's/.*Machine[: ]*//; s/^[ \t]*//')
	fi
	
	# Return the model if found
	if [ -n "$model" ]; then
		echo "$model"
		return 0
	fi
	
	# Return empty if not found
	echo ""
	return 1
}

# Echo out the machine model
echo "[INFO] Machine model detected: $(get_machine_model)"

# If machine model does not equal REQUIRED_HARDWARE exit the script
if [ "$(get_machine_model)" != "$REQUIRED_HARDWARE" ]; then
    echo "[ERROR] Machine model is not $REQUIRED_HARDWARE, exiting script"
    exit 1
fi


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
else
    echo "[INFO] wpad-basic-mbedtls is not installed"
fi

echo "[INFO] Checking and removing wpad-basic-wolfssl package..."
if opkg list-installed | grep wpad-basic-wolfssl > /dev/null; then
    echo "[INFO] Removing wpad-basic-wolfssl (incompatible with mesh)"
    opkg remove wpad-basic-wolfssl
    echo "[SUCCESS] wpad-basic-wolfssl removed"
else
    echo "[INFO] wpad-basic-wolfssl is not installed"
fi

# Update package lists once before installing all packages
echo "[INFO] Updating package lists..."
opkg update

echo "[INFO] Checking and installing wpad-mesh-openssl package..."
if opkg list-installed | grep wpad-mesh-openssl > /dev/null; then
    echo "[INFO] wpad-mesh-openssl is already installed"
else
    echo "[INFO] Installing wpad-mesh-openssl..."
    opkg install wpad-mesh-openssl
    echo "[SUCCESS] wpad-mesh-openssl installed"
fi

echo "[INFO] Checking and installing kmod-batman-adv package..."
if opkg list-installed | grep kmod-batman-adv > /dev/null; then
    echo "[INFO] kmod-batman-adv is already installed"
else
    echo "[INFO] Installing kmod-batman-adv..."
    opkg install kmod-batman-adv
    echo "[SUCCESS] kmod-batman-adv installed"
fi

echo "[INFO] Checking and installing batctl-default package..."
if opkg list-installed | grep batctl-default > /dev/null; then
    echo "[INFO] batctl-default is already installed"
else
    echo "[INFO] Installing batctl-default..."
    opkg install batctl-default
    echo "[SUCCESS] batctl-default installed"
fi


# ====================================================================
# STEP 3: Set system information
# ====================================================================
echo "[INFO] Setting system hostname to $router_name..."
uci set system.@system[0].hostname=${router_name}
uci commit system


echo "[INFO] Setting system timezone to $router_timezone_name.."
uci set system.@system[0].zonename=${router_timezone_name}
uci set system.@system[0].timezone=${router_timezone}
uci commit system

# ====================================================================
# STEP 4: Create the guest network interface
# ====================================================================

uci -q batch << EOI
# Create bridge device for guest network
delete network.${guest_net_id}_dev
set network.${guest_net_id}_dev=device
set network.${guest_net_id}_dev.type=bridge
set network.${guest_net_id}_dev.name=br-${guest_net_id}

# Create guest network interface
delete network.${guest_net_id}
set network.${guest_net_id}=interface
set network.${guest_net_id}.proto=static
set network.${guest_net_id}.device=br-${guest_net_id}
set network.${guest_net_id}.ipaddr=${guest_ipaddr}/24

# Commit the changes
commit network

# Configure guest WiFi (WPA3-SAE with WPA2-PSK fallback)

# Enable the radio device first
delete wireless.${guest_wifi_device}.disabled
set wireless.${guest_wifi_device}.channel=${guest_channel}
set wireless.${guest_wifi_device}.country=US
set wireless.${guest_wifi_device}.cell_density=0

# Create guest WiFi interface
delete wireless.${guest_net_id}
set wireless.${guest_net_id}=wifi-iface
set wireless.${guest_net_id}.device=${guest_wifi_device}
set wireless.${guest_net_id}.mode=ap
set wireless.${guest_net_id}.network=${guest_net_id}
set wireless.${guest_net_id}.ssid='${guest_ssid}'
set wireless.${guest_net_id}.encryption=psk2
set wireless.${guest_net_id}.key=${guest_pwd}

set wireless.${guest_net_id}.ocv=0
set wireless.${guest_net_id}.mobility_domain=${mobility_domain}
set wireless.${guest_net_id}.ieee80211r=1
set wireless.${guest_net_id}.ft_over_ds=0
set wireless.${guest_net_id}.isolate='1'
set wireless.${guest_net_id}.ft_psk_generate_local='1'

delete wireless.${guest_net_id}.disabled

commit wireless

delete dhcp.${guest_net_id}
set dhcp.${guest_net_id}=dhcp
set dhcp.${guest_net_id}.interface=${guest_net_id}
set dhcp.${guest_net_id}.start=100  # Start at .100
set dhcp.${guest_net_id}.limit=150  # 150 addresses available
set dhcp.${guest_net_id}.leasetime=1h

commit dhcp

# Create guest network firewall zone (isolated)
delete firewall.${guest_net_id}
set firewall.${guest_net_id}=zone
set firewall.${guest_net_id}.name=${guest_net_id}Zone
set firewall.${guest_net_id}.network=${guest_net_id}
set firewall.${guest_net_id}.input=REJECT  # Block incoming by default
set firewall.${guest_net_id}.output=ACCEPT  # Allow outgoing
set firewall.${guest_net_id}.forward=REJECT  # Isolate guests

# Allow DNS queries from guest network to router
delete firewall.${guest_net_id}_dns
set firewall.${guest_net_id}_dns=rule
set firewall.${guest_net_id}_dns.name=Allow-DNS-${guest_net_id}
set firewall.${guest_net_id}_dns.src=${guest_net_id}Zone
set firewall.${guest_net_id}_dns.dest_port=53  # DNS port
add_list firewall.${guest_net_id}_dns.proto=tcp
add_list firewall.${guest_net_id}_dns.proto=udp
set firewall.${guest_net_id}_dns.target=ACCEPT

# Allow DHCP requests from guest network to router
delete firewall.${guest_net_id}_dhcp
set firewall.${guest_net_id}_dhcp=rule
set firewall.${guest_net_id}_dhcp.name=Allow-DHCP-${guest_net_id}
set firewall.${guest_net_id}_dhcp.src=${guest_net_id}Zone
set firewall.${guest_net_id}_dhcp.dest_port=67
set firewall.${guest_net_id}_dhcp.proto=udp
set firewall.${guest_net_id}_dhcp.family=ipv4
set firewall.${guest_net_id}_dhcp.target=ACCEPT

# Allow guest network to access internet via WAN
delete firewall.${guest_net_id}_wan
set firewall.${guest_net_id}_wan=forwarding
set firewall.${guest_net_id}_wan.src=${guest_net_id}Zone
set firewall.${guest_net_id}_wan.dest=${FW_WAN}

commit firewall

EOI

# ====================================================================
# STEP 4: Create the IoT network interface
# ====================================================================

uci -q batch << EOI
# Create bridge device for IoT network
delete network.${iot_net_id}_dev
set network.${iot_net_id}_dev=device
set network.${iot_net_id}_dev.type=bridge
set network.${iot_net_id}_dev.name=br-${iot_net_id}

# Create IoT network interface
delete network.${iot_net_id}
set network.${iot_net_id}=interface
set network.${iot_net_id}.proto=static
set network.${iot_net_id}.device=br-${iot_net_id}
set network.${iot_net_id}.ipaddr=${iot_ipaddr}/24

# Commit the changes
commit network

# Enable the radio device first
delete wireless.${iot_wifi_device}.disabled
set wireless.${iot_wifi_device}.channel=${iot_channel}
set wireless.${iot_wifi_device}.country=US
set wireless.${iot_wifi_device}.cell_density=0

# Create guest WiFi interface
delete wireless.${iot_net_id}
set wireless.${iot_net_id}=wifi-iface
set wireless.${iot_net_id}.device=${iot_wifi_device}
set wireless.${iot_net_id}.mode=ap
set wireless.${iot_net_id}.network=${iot_net_id}
set wireless.${iot_net_id}.ssid='${iot_ssid}'
set wireless.${iot_net_id}.encryption=psk2
set wireless.${iot_net_id}.key=${iot_pwd}

set wireless.${iot_net_id}.ocv=0
set wireless.${iot_net_id}.mobility_domain=${mobility_domain}
set wireless.${iot_net_id}.ieee80211r=1
set wireless.${iot_net_id}.ft_over_ds=0

delete wireless.${iot_net_id}.disabled

commit wireless

delete dhcp.${iot_net_id}
set dhcp.${iot_net_id}=dhcp
set dhcp.${iot_net_id}.interface=${iot_net_id}
set dhcp.${iot_net_id}.start=100  # Start at .100
set dhcp.${iot_net_id}.limit=150  # 150 addresses available
set dhcp.${iot_net_id}.leasetime=1h

commit dhcp

# Create IoT network firewall zone (isolated)
delete firewall.${iot_net_id}
set firewall.${iot_net_id}=zone
set firewall.${iot_net_id}.name=${iot_net_id}Zone
set firewall.${iot_net_id}.network=${iot_net_id}
set firewall.${iot_net_id}.input=REJECT
set firewall.${iot_net_id}.output=ACCEPT
set firewall.${iot_net_id}.forward=REJECT

# Allow DNS queries from IoT network to router
delete firewall.${iot_net_id}_dns
set firewall.${iot_net_id}_dns=rule
set firewall.${iot_net_id}_dns.name=Allow-DNS-${iot_net_id}
set firewall.${iot_net_id}_dns.src=${iot_net_id}Zone
set firewall.${iot_net_id}_dns.dest_port=53  # DNS port
add_list firewall.${iot_net_id}_dns.proto=tcp
add_list firewall.${iot_net_id}_dns.proto=udp
set firewall.${iot_net_id}_dns.target=ACCEPT

# Allow DHCP requests from IoT network to router
delete firewall.${iot_net_id}_dhcp
set firewall.${iot_net_id}_dhcp=rule
set firewall.${iot_net_id}_dhcp.name=Allow-DHCP-${iot_net_id}
set firewall.${iot_net_id}_dhcp.src=${iot_net_id}Zone
set firewall.${iot_net_id}_dhcp.dest_port=67
set firewall.${iot_net_id}_dhcp.proto=udp
set firewall.${iot_net_id}_dhcp.family=ipv4
set firewall.${iot_net_id}_dhcp.target=ACCEPT

# Allow guest network to access internet via WAN
delete firewall.${iot_net_id}_wan
set firewall.${iot_net_id}_wan=forwarding
set firewall.${iot_net_id}_wan.src=${iot_net_id}Zone
set firewall.${iot_net_id}_wan.dest=${FW_WAN}

commit firewall

EOI
















# ====================================================================
# STEP 5: Apply configuration changes
# ====================================================================
echo "[INFO] Reload the system service..."
/etc/init.d/system reload

echo "[INFO] Restarting wpad service to apply changes..."
wifi down
/etc/init.d/wpad restart
wifi up

echo "[INFO] Restarting network services to apply changes..."
service network reload
service dnsmasq restart
service firewall restart
echo "[SUCCESS] All services restarted successfully"