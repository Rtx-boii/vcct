#!/bin/sh
set -e

echo "Starting named DNS server with options: $DNS_OPTIONS"

# Explicitly specify the config file with '-c'
exec /usr/sbin/named -c /etc/named.conf $DNS_OPTIONS
