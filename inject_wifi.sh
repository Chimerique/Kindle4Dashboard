#!/bin/sh
# Inject NoTrespassing into wifid's wpa_supplicant network list
# Run this after wifid has started wpa_supplicant
IFACE="wlan0"
SSID="NoTrespassing"
PSK_HASH="9dc6b9e281f746e118d0def9c328456ae4da79a94e97875b9703ee38a6540809"

NID=$(wpa_cli -i "$IFACE" add_network 2>/dev/null)
echo "Added network ID: $NID"

wpa_cli -i "$IFACE" set_network "$NID" ssid "\"$SSID\""
wpa_cli -i "$IFACE" set_network "$NID" psk $PSK_HASH
wpa_cli -i "$IFACE" set_network "$NID" key_mgmt WPA-PSK
wpa_cli -i "$IFACE" set_network "$NID" priority 100
wpa_cli -i "$IFACE" enable_network "$NID"
wpa_cli -i "$IFACE" select_network "$NID"

echo "Waiting for connection..."
sleep 15

wpa_cli -i "$IFACE" status
ifconfig "$IFACE" | grep inet

# Try to obtain IP via DHCP if connected
WPA_STATE=$(wpa_cli -i "$IFACE" status 2>/dev/null | grep 'wpa_state=' | cut -d= -f2)
if [ "$WPA_STATE" = "COMPLETED" ]; then
    echo "WPA2 connected, running DHCP..."
    udhcpc -i "$IFACE" -n -q -t 5 2>/dev/null
    echo "IP after DHCP:"
    ifconfig "$IFACE" | grep inet
fi
