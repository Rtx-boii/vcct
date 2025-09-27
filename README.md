This repository contains Dockerfiles and configuration files for setting up:

1. DHCP Server
2. DNS Server (BIND)
3. Squid Proxy Server

Contents:
- Dockerfiles for building each service container
- Configuration files (dhcpd.conf, named.conf, squid.conf, etc.)
- Supporting files such as blocked sites, banned keywords, and volume mappings

Usage:
- Build the images using Docker or Docker Compose
- Run the containers with attached configuration and volume mappings
- Adjust configurations as needed for your network setup
