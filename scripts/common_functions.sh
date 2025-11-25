#!/bin/ash

# Common functions library for OpenWrt router setup scripts
# This file should be sourced by router-specific setup scripts

# ====================================================================
# Hardware Detection Functions
# ====================================================================

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

# Validate hardware model
validate_hardware() {
	local required_hardware="$1"
	local detected_model
	
	detected_model=$(get_machine_model)
	echo "[INFO] Machine model detected: $detected_model"
	
	if [ "$detected_model" != "$required_hardware" ]; then
		echo "[ERROR] Machine model is not $required_hardware, exiting script"
		return 1
	fi
	
	return 0
}

# ====================================================================
# Package Management Functions
# ====================================================================

# Remove a package if installed
remove_package_if_installed() {
	local package_name="$1"
	
	echo "[INFO] Checking and removing $package_name package..."
	if opkg list-installed | grep "$package_name" > /dev/null; then
		echo "[INFO] Removing $package_name (incompatible with mesh)"
		if ! opkg remove "$package_name"; then
			echo "[ERROR] Failed to remove $package_name"
			return 1
		fi
		echo "[SUCCESS] $package_name removed"
	else
		echo "[INFO] $package_name is not installed"
	fi
	return 0
}

# Install a package if not already installed
install_package_if_needed() {
	local package_name="$1"
	
	echo "[INFO] Checking and installing $package_name package..."
	if opkg list-installed | grep "$package_name" > /dev/null; then
		echo "[INFO] $package_name is already installed"
	else
		echo "[INFO] Installing $package_name..."
		if ! opkg install "$package_name"; then
			echo "[ERROR] Failed to install $package_name"
			return 1
		fi
		echo "[SUCCESS] $package_name installed"
	fi
	return 0
}

# Update package lists
update_packages() {
	echo "[INFO] Updating package lists..."
	if ! opkg update; then
		echo "[ERROR] Failed to update package lists"
		return 1
	fi
	return 0
}

# Install required packages for mesh networking
install_mesh_packages() {
	# Remove incompatible packages
	remove_package_if_installed "wpad-basic-mbedtls" || return 1
	remove_package_if_installed "wpad-basic-wolfssl" || return 1
	
	# Update package lists
	update_packages || return 1
	
	# Install required packages
	install_package_if_needed "wpad-mesh-openssl" || return 1
	install_package_if_needed "kmod-batman-adv" || return 1
	install_package_if_needed "batctl-default" || return 1
	
	return 0
}

# ====================================================================
# System Configuration Functions
# ====================================================================

# Set system hostname
set_hostname() {
	local hostname="$1"
	
	echo "[INFO] Setting system hostname to $hostname..."
	uci set system.@system[0].hostname="$hostname"
	if ! uci commit system; then
		echo "[ERROR] Failed to commit system hostname changes"
		return 1
	fi
	return 0
}

# Set system timezone
set_timezone() {
	local timezone_name="$1"
	local timezone="$2"
	
	echo "[INFO] Setting system timezone to $timezone_name..."
	uci set system.@system[0].zonename="$timezone_name"
	uci set system.@system[0].timezone="$timezone"
	if ! uci commit system; then
		echo "[ERROR] Failed to commit system timezone changes"
		return 1
	fi
	return 0
}

# ====================================================================
# Network Configuration Functions
# ====================================================================

# Detect WAN interface for firewall configuration
detect_wan_interface() {
	echo "[INFO] Detecting WAN interface for firewall rules..."
	. /lib/functions/network.sh
	network_flush_cache
	network_find_wan NET_IF
	FW_WAN="$(fw4 -q network ${NET_IF})"
	echo "[INFO] WAN interface detected: $NET_IF (firewall zone: $FW_WAN)"
	
	# Export for use in calling script
	export NET_IF
	export FW_WAN
}

# Create VLAN on a bridge interface
# Parameters: vlan_id, bridge_device, vlan_tag
create_vlan() {
	local vlan_id="$1"
	local bridge_device="$2"
	local vlan_tag="$3"
	
	echo "[INFO] Creating VLAN ${vlan_tag} on ${bridge_device}..."
	
	uci -q batch << EOI
# Create VLAN device
delete network.${vlan_id}_vlan
set network.${vlan_id}_vlan=device
set network.${vlan_id}_vlan.type=8021q
set network.${vlan_id}_vlan.ifname=${bridge_device}
set network.${vlan_id}_vlan.vid=${vlan_tag}
set network.${vlan_id}_vlan.name=${bridge_device}.${vlan_tag}

commit network
EOI
}

# Create a network with WiFi interface and firewall rules
# Parameters: net_id, ipaddr, ssid, pwd, channel, wifi_device, mobility_domain, fw_wan, isolate_clients, allow_router_access, vlan_tag (optional)
create_network() {
	local net_id="$1"
	local ipaddr="$2"
	local ssid="$3"
	local pwd="$4"
	local channel="$5"
	local wifi_device="$6"
	local mobility_domain="$7"
	local fw_wan="$8"
	local isolate_clients="${9:-0}"  # Default: don't isolate
	local allow_router_access="${10:-0}"  # Default: no router access
	local vlan_tag="${11:-}"  # Optional: VLAN tag
	
	# If VLAN tag is specified, configure VLAN-aware bridge
	if [ -n "$vlan_tag" ]; then
		echo "[INFO] Configuring VLAN ${vlan_tag} for ${net_id} network..."
		uci -q batch << EOI
# Create bridge device for $net_id network with VLAN support
delete network.${net_id}_dev
set network.${net_id}_dev=device
set network.${net_id}_dev.type=bridge
set network.${net_id}_dev.name=br-${net_id}
set network.${net_id}_dev.vlan_filtering=1

# Create bridge VLAN entry
delete network.${net_id}_vlan
set network.${net_id}_vlan=bridge-vlan
set network.${net_id}_vlan.device=br-${net_id}
set network.${net_id}_vlan.vlan=${vlan_tag}
add_list network.${net_id}_vlan.ports='*:u'

# Create $net_id network interface
delete network.${net_id}
set network.${net_id}=interface
set network.${net_id}.proto=static
set network.${net_id}.device=br-${net_id}.${vlan_tag}
set network.${net_id}.ipaddr=${ipaddr}/24

commit network
EOI
	else
		uci -q batch << EOI
# Create bridge device for $net_id network
delete network.${net_id}_dev
set network.${net_id}_dev=device
set network.${net_id}_dev.type=bridge
set network.${net_id}_dev.name=br-${net_id}

# Create $net_id network interface
delete network.${net_id}
set network.${net_id}=interface
set network.${net_id}.proto=static
set network.${net_id}.device=br-${net_id}
set network.${net_id}.ipaddr=${ipaddr}/24

commit network
EOI
	fi

	uci -q batch << EOI
# Enable the radio device first
delete wireless.${wifi_device}.disabled
set wireless.${wifi_device}.channel=${channel}
set wireless.${wifi_device}.country=US
set wireless.${wifi_device}.cell_density=0

# Create $net_id WiFi interface
delete wireless.${net_id}
set wireless.${net_id}=wifi-iface
set wireless.${net_id}.device=${wifi_device}
set wireless.${net_id}.mode=ap
set wireless.${net_id}.network=${net_id}
set wireless.${net_id}.ssid='${ssid}'
set wireless.${net_id}.encryption=psk2+ccmp
set wireless.${net_id}.key=${pwd}

set wireless.${net_id}.ocv=0
set wireless.${net_id}.mobility_domain=${mobility_domain}
set wireless.${net_id}.ieee80211r=1
set wireless.${net_id}.ft_over_ds=0
EOI

	# Add isolation if requested
	if [ "$isolate_clients" = "1" ]; then
		uci -q batch << EOI
set wireless.${net_id}.isolate='1'
set wireless.${net_id}.ft_psk_generate_local='1'
EOI
	fi

	uci -q batch << EOI
delete wireless.${net_id}.disabled

commit wireless

# Configure DHCP
delete dhcp.${net_id}
set dhcp.${net_id}=dhcp
set dhcp.${net_id}.interface=${net_id}
set dhcp.${net_id}.start=100
set dhcp.${net_id}.limit=150
set dhcp.${net_id}.leasetime=1h

commit dhcp

# Create $net_id network firewall zone
delete firewall.${net_id}
set firewall.${net_id}=zone
set firewall.${net_id}.name=${net_id}Zone
set firewall.${net_id}.network=${net_id}
set firewall.${net_id}.input=REJECT
set firewall.${net_id}.output=ACCEPT
EOI

	# Set forward policy based on router access
	if [ "$allow_router_access" = "1" ]; then
		uci set firewall.${net_id}.forward=ACCEPT
	else
		uci set firewall.${net_id}.forward=REJECT
	fi

	uci -q batch << EOI
# Allow DNS queries from $net_id network to router
delete firewall.${net_id}_dns
set firewall.${net_id}_dns=rule
set firewall.${net_id}_dns.name=Allow-DNS-${net_id}
set firewall.${net_id}_dns.src=${net_id}Zone
set firewall.${net_id}_dns.dest_port=53
add_list firewall.${net_id}_dns.proto=tcp
add_list firewall.${net_id}_dns.proto=udp
set firewall.${net_id}_dns.target=ACCEPT

# Allow DHCP requests from $net_id network to router
delete firewall.${net_id}_dhcp
set firewall.${net_id}_dhcp=rule
set firewall.${net_id}_dhcp.name=Allow-DHCP-${net_id}
set firewall.${net_id}_dhcp.src=${net_id}Zone
set firewall.${net_id}_dhcp.dest_port=67
set firewall.${net_id}_dhcp.proto=udp
set firewall.${net_id}_dhcp.family=ipv4
set firewall.${net_id}_dhcp.target=ACCEPT
EOI

	# Add router access rules if requested
	if [ "$allow_router_access" = "1" ]; then
		uci -q batch << EOI
# Allow SSH access from $net_id network to router
delete firewall.${net_id}_ssh
set firewall.${net_id}_ssh=rule
set firewall.${net_id}_ssh.name=Allow-SSH-${net_id}
set firewall.${net_id}_ssh.src=${net_id}Zone
set firewall.${net_id}_ssh.dest_port=22
set firewall.${net_id}_ssh.proto=tcp
set firewall.${net_id}_ssh.target=ACCEPT

# Allow LuCI web interface access from $net_id network to router
delete firewall.${net_id}_luci
set firewall.${net_id}_luci=rule
set firewall.${net_id}_luci.name=Allow-LuCI-${net_id}
set firewall.${net_id}_luci.src=${net_id}Zone
add_list firewall.${net_id}_luci.dest_port=80
add_list firewall.${net_id}_luci.dest_port=443
set firewall.${net_id}_luci.proto=tcp
set firewall.${net_id}_luci.target=ACCEPT
EOI
	fi

	uci -q batch << EOI
# Allow $net_id network to access internet via WAN
delete firewall.${net_id}_wan
set firewall.${net_id}_wan=forwarding
set firewall.${net_id}_wan.src=${net_id}Zone
set firewall.${net_id}_wan.dest=${fw_wan}

commit firewall
EOI
}

# Create firewall forwarding rule between zones
# Parameters: src_zone, dest_zone, rule_name
create_zone_forwarding() {
	local src_zone="$1"
	local dest_zone="$2"
	local rule_name="$3"
	
	echo "[INFO] Creating forwarding rule: ${src_zone} -> ${dest_zone}..."
	
	uci -q batch << EOI
# Allow forwarding from ${src_zone} to ${dest_zone}
delete firewall.${rule_name}
set firewall.${rule_name}=forwarding
set firewall.${rule_name}.name=${rule_name}
set firewall.${rule_name}.src=${src_zone}
set firewall.${rule_name}.dest=${dest_zone}

commit firewall
EOI
}

# ====================================================================
# Service Management Functions
# ====================================================================

# Restart all services to apply configuration
restart_services() {
	echo "[INFO] Reload the system service..."
	if ! /etc/init.d/system reload; then
		echo "[WARNING] Failed to reload system service (non-critical)"
	fi

	echo "[INFO] Restarting wpad service to apply changes..."
	wifi down
	if ! /etc/init.d/wpad restart; then
		echo "[ERROR] Failed to restart wpad service"
		return 1
	fi
	wifi up

	echo "[INFO] Restarting network services to apply changes..."
	if ! service network reload; then
		echo "[ERROR] Failed to reload network service"
		return 1
	fi

	if ! service dnsmasq restart; then
		echo "[ERROR] Failed to restart dnsmasq service"
		return 1
	fi

	if ! service firewall restart; then
		echo "[ERROR] Failed to restart firewall service"
		return 1
	fi

	echo "[SUCCESS] All services restarted successfully"
	return 0
}

# ====================================================================
# Cleanup Functions
# ====================================================================

# Delete default OpenWrt radio configurations
delete_default_radios() {
	local radios="$@"
	
	echo "[INFO] Deleting OpenWrt default radios..."
	for radio in $radios; do
		uci delete wireless.default_${radio} 2>/dev/null || true
	done
	uci commit wireless
}
