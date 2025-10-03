FROM rockylinux:9 AS builder
WORKDIR /squid-build


RUN dnf install -y squid && dnf clean all

# Copy the default Squid configuration files to /squid-build
RUN cp -r /etc/squid ./


FROM alpine:latest

RUN apk add --no-cache squid bash

# Create required directories for logs and cache, set ownership to 'squid'
RUN mkdir -p /var/log/squid /var/spool/squid && \
    chown -R squid:squid /var/log/squid /var/spool/squid

# Set working directory for Squid configs
WORKDIR /etc/squid

# Copy default Squid configs from builder stage
COPY --from=builder /squid-build/squid/ ./

# Copy your custom configuration and ACL files
COPY squid.conf .
COPY banned-keywords .
COPY blocked-filextensions .
COPY blocked-sites .

# Copy the startup script and make it executable
COPY start-squid.sh /usr/local/bin/start-squid.sh
RUN chmod +x /usr/local/bin/start-squid.sh

# Expose Squid default port
EXPOSE 3128

# Start Squid via the entrypoint script (runs in foreground)
CMD ["/usr/local/bin/start-squid.sh"]
