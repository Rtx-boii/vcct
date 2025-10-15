#!/bin/sh

CACHE_DIR="/var/spool/squid"

echo "Ensuring base directories exist..."
mkdir -p /var/log/squid ${CACHE_DIR}
chown -R squid:squid /var/log/squid ${CACHE_DIR}

echo "Creating full two-level cache structure..."
# Loop for the first-level directories (00 to 0F)
for i in $(seq 0 15); do
    L1_DIR=$(printf '%02X' $i)
    # Loop for the second-level directories (00 to FF)
    for j in $(seq 0 255); do
        L2_DIR=$(printf '%02X' $j)
        mkdir -p "${CACHE_DIR}/${L1_DIR}/${L2_DIR}"
    done
done

echo "Setting final permissions..."
chown -R squid:squid ${CACHE_DIR}



echo "Setup complete. Starting Squid..."
exec /usr/sbin/squid -N -d 1
