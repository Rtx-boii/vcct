#!/bin/sh
set -e

# The Kea configuration listens on all interfaces by default,
# so we don't strictly need the DHCP_INTERFACE variable, but it's
# good practice to leave the check in case of future changes.
if [ -z "$DHCP_INTERFACE" ]; then
    echo "Warning: DHCP_INTERFACE is not set. Kea will listen on all interfaces."
fi

# Execute the Kea DHCPv4 server in the foreground
exec /usr/sbin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
