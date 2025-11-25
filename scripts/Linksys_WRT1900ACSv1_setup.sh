#!/bin/ash

REQUIRED_HARDWARE="Linksys WRT1900ACS"

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
    if ! opkg remove wpad-basic-mbedtls; then
        echo "[ERROR] Failed to remove wpad-basic-mbedtls"
        exit 1
    fi
    echo "[SUCCESS] wpad-basic-mbedtls removed"
else
    echo "[INFO] wpad-basic-mbedtls is not installed"
fi

echo "[INFO] Checking and removing wpad-basic-wolfssl package..."
if opkg list-installed | grep wpad-basic-wolfssl > /dev/null; then
    echo "[INFO] Removing wpad-basic-wolfssl (incompatible with mesh)"
    if ! opkg remove wpad-basic-wolfssl; then
        echo "[ERROR] Failed to remove wpad-basic-wolfssl"
        exit 1
    fi
    echo "[SUCCESS] wpad-basic-wolfssl removed"
else
    echo "[INFO] wpad-basic-wolfssl is not installed"
fi

# Update package lists once before installing all packages
echo "[INFO] Updating package lists..."
if ! opkg update; then
    echo "[ERROR] Failed to update package lists"
    exit 1
fi

echo "[INFO] Checking and installing wpad-mesh-openssl package..."
if opkg list-installed | grep wpad-mesh-openssl > /dev/null; then
    echo "[INFO] wpad-mesh-openssl is already installed"
else
    echo "[INFO] Installing wpad-mesh-openssl..."
    if ! opkg install wpad-mesh-openssl; then
        echo "[ERROR] Failed to install wpad-mesh-openssl"
        exit 1
    fi
    echo "[SUCCESS] wpad-mesh-openssl installed"
fi

echo "[INFO] Checking and installing kmod-batman-adv package..."
if opkg list-installed | grep kmod-batman-adv > /dev/null; then
    echo "[INFO] kmod-batman-adv is already installed"
else
    echo "[INFO] Installing kmod-batman-adv..."
    if ! opkg install kmod-batman-adv; then
        echo "[ERROR] Failed to install kmod-batman-adv"
        exit 1
    fi
    echo "[SUCCESS] kmod-batman-adv installed"
fi

echo "[INFO] Checking and installing batctl-default package..."
if opkg list-installed | grep batctl-default > /dev/null; then
    echo "[INFO] batctl-default is already installed"
else
    echo "[INFO] Installing batctl-default..."
    if ! opkg install batctl-default; then
        echo "[ERROR] Failed to install batctl-default"
        exit 1
    fi
    echo "[SUCCESS] batctl-default installed"
fi


# ====================================================================
# STEP 3: Set system information
# ====================================================================
echo "[INFO] Setting system hostname to $router_name..."
uci set system.@system[0].hostname=${router_name}
if ! uci commit system; then
    echo "[ERROR] Failed to commit system hostname changes"
    exit 1
fi

echo "[INFO] Setting system timezone to $router_timezone_name.."
uci set system.@system[0].zonename=${router_timezone_name}
uci set system.@system[0].timezone=${router_timezone}
if ! uci commit system; then
    echo "[ERROR] Failed to commit system timezone changes"
    exit 1
fi

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
set wireless.${guest_net_id}.encryption=psk2+ccmp
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
# STEP 5: Create the IoT network interface
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

# Create IoT WiFi interface
delete wireless.${iot_net_id}
set wireless.${iot_net_id}=wifi-iface
set wireless.${iot_net_id}.device=${iot_wifi_device}
set wireless.${iot_net_id}.mode=ap
set wireless.${iot_net_id}.network=${iot_net_id}
set wireless.${iot_net_id}.ssid='${iot_ssid}'
set wireless.${iot_net_id}.encryption=psk2+ccmp
set wireless.${iot_net_id}.key=${iot_pwd}

set wireless.${iot_net_id}.ocv=0
set wireless.${iot_net_id}.mobility_domain=${mobility_domain}
set wireless.${iot_net_id}.ieee80211r=1
set wireless.${iot_net_id}.ft_over_ds=0
set wireless.${iot_net_id}.isolate='1'
set wireless.${iot_net_id}.ft_psk_generate_local='1'

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

# Allow IoT network to access internet via WAN
delete firewall.${iot_net_id}_wan
set firewall.${iot_net_id}_wan=forwarding
set firewall.${iot_net_id}_wan.src=${iot_net_id}Zone
set firewall.${iot_net_id}_wan.dest=${FW_WAN}

commit firewall

EOI

# ====================================================================
# STEP 6: Create the Home network interface
# ====================================================================
uci -q batch << EOI
# Create bridge device for Home network
delete network.${home_net_id}_dev
set network.${home_net_id}_dev=device
set network.${home_net_id}_dev.type=bridge
set network.${home_net_id}_dev.name=br-${home_net_id}

# Create Home network interface
delete network.${home_net_id}
set network.${home_net_id}=interface
set network.${home_net_id}.proto=static
set network.${home_net_id}.device=br-${home_net_id}
set network.${home_net_id}.ipaddr=${home_ipaddr}/24

# Commit the changes
commit network

# Enable the radio device first
delete wireless.${home_wifi_device}.disabled
set wireless.${home_wifi_device}.channel=${home_channel}
set wireless.${home_wifi_device}.country=US
set wireless.${home_wifi_device}.cell_density=0

# Create Home WiFi interface
delete wireless.${home_net_id}
set wireless.${home_net_id}=wifi-iface
set wireless.${home_net_id}.device=${home_wifi_device}
set wireless.${home_net_id}.mode=ap
set wireless.${home_net_id}.network=${home_net_id}
set wireless.${home_net_id}.ssid='${home_ssid}'
set wireless.${home_net_id}.encryption=psk2+ccmp
set wireless.${home_net_id}.key=${home_pwd}

set wireless.${home_net_id}.ocv=0
set wireless.${home_net_id}.mobility_domain=${mobility_domain}
set wireless.${home_net_id}.ieee80211r=1
set wireless.${home_net_id}.ft_over_ds=0

delete wireless.${home_net_id}.disabled

commit wireless

delete dhcp.${home_net_id}
set dhcp.${home_net_id}=dhcp
set dhcp.${home_net_id}.interface=${home_net_id}
set dhcp.${home_net_id}.start=100  # Start at .100
set dhcp.${home_net_id}.limit=150  # 150 addresses available
set dhcp.${home_net_id}.leasetime=1h

commit dhcp

# Create Home network firewall zone (isolated)
delete firewall.${home_net_id}
set firewall.${home_net_id}=zone
set firewall.${home_net_id}.name=${home_net_id}Zone
set firewall.${home_net_id}.network=${home_net_id}
set firewall.${home_net_id}.input=REJECT
set firewall.${home_net_id}.output=ACCEPT
set firewall.${home_net_id}.forward=ACCEPT

# Allow DNS queries from Home network to router
delete firewall.${home_net_id}_dns
set firewall.${home_net_id}_dns=rule
set firewall.${home_net_id}_dns.name=Allow-DNS-${home_net_id}
set firewall.${home_net_id}_dns.src=${home_net_id}Zone
set firewall.${home_net_id}_dns.dest_port=53  # DNS port
add_list firewall.${home_net_id}_dns.proto=tcp
add_list firewall.${home_net_id}_dns.proto=udp
set firewall.${home_net_id}_dns.target=ACCEPT

# Allow DHCP requests from Home network to router
delete firewall.${home_net_id}_dhcp
set firewall.${home_net_id}_dhcp=rule
set firewall.${home_net_id}_dhcp.name=Allow-DHCP-${home_net_id}
set firewall.${home_net_id}_dhcp.src=${home_net_id}Zone
set firewall.${home_net_id}_dhcp.dest_port=67
set firewall.${home_net_id}_dhcp.proto=udp
set firewall.${home_net_id}_dhcp.family=ipv4
set firewall.${home_net_id}_dhcp.target=ACCEPT

# Allow SSH access from Home network to router
delete firewall.${home_net_id}_ssh
set firewall.${home_net_id}_ssh=rule
set firewall.${home_net_id}_ssh.name=Allow-SSH-${home_net_id}
set firewall.${home_net_id}_ssh.src=${home_net_id}Zone
set firewall.${home_net_id}_ssh.dest_port=22
set firewall.${home_net_id}_ssh.proto=tcp
set firewall.${home_net_id}_ssh.target=ACCEPT

# Allow LuCI web interface access from Home network to router
delete firewall.${home_net_id}_luci
set firewall.${home_net_id}_luci=rule
set firewall.${home_net_id}_luci.name=Allow-LuCI-${home_net_id}
set firewall.${home_net_id}_luci.src=${home_net_id}Zone
add_list firewall.${home_net_id}_luci.dest_port=80
add_list firewall.${home_net_id}_luci.dest_port=443
set firewall.${home_net_id}_luci.proto=tcp
set firewall.${home_net_id}_luci.target=ACCEPT

# Allow Home network to access internet via WAN
delete firewall.${home_net_id}_wan
set firewall.${home_net_id}_wan=forwarding
set firewall.${home_net_id}_wan.src=${home_net_id}Zone
set firewall.${home_net_id}_wan.dest=${FW_WAN}

commit firewall

EOI

# ====================================================================
# STEP 7: Delete OpenWrt default radios
# ====================================================================
echo "[INFO] Deleting OpenWrt default radios..."
uci delete wireless.default_radio0
uci delete wireless.default_radio1
uci commit wireless

# ====================================================================
# STEP 8: Apply configuration changes
# ====================================================================
echo "[INFO] Reload the system service..."
if ! /etc/init.d/system reload; then
    echo "[WARNING] Failed to reload system service (non-critical)"
fi

echo "[INFO] Restarting wpad service to apply changes..."
wifi down
if ! /etc/init.d/wpad restart; then
    echo "[ERROR] Failed to restart wpad service"
    exit 1
fi
wifi up

echo "[INFO] Restarting network services to apply changes..."
if ! service network reload; then
    echo "[ERROR] Failed to reload network service"
    exit 1
fi

if ! service dnsmasq restart; then
    echo "[ERROR] Failed to restart dnsmasq service"
    exit 1
fi

if ! service firewall restart; then
    echo "[ERROR] Failed to restart firewall service"
    exit 1
fi

echo "[SUCCESS] All services restarted successfully"
