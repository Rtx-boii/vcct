#!/bin/sh
set -e
if [ -n "$DHCP_INTERFACE" ]; then
    exec /usr/sbin/dhcpd -f -d "$DHCP_INTERFACE"
else
    exec /usr/sbin/dhcpd -f -d
fi
