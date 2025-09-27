FROM rockylinux:9 AS builder
WORKDIR /squid-build
RUN dnf install -y squid && dnf clean all
RUN cp -r /etc/squid ./

FROM alpine:latest
RUN apk add --no-cache squid

RUN mkdir -p /var/log/squid /var/spool/squid && chown -R squid:squid /var/log/squid /var/spool/squid

WORKDIR /etc/squid
COPY --from=builder /squid-build/squid/ ./

COPY squid.conf .
COPY banned-keywords .
COPY blocked-filextensions .
COPY blocked-sites .

# This part is correct
COPY start-squid.sh /start-squid.sh
RUN chmod +x /start-squid.sh

EXPOSE 3128

# This is also correct
CMD ["/start-squid.sh"]
