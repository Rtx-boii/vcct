FROM rockylinux:9 AS builder

WORKDIR /build

RUN dnf install -y dhcp-server && dnf clean all
RUN mkdir -p /runtime/usr/sbin /runtime/lib64 /runtime/etc/dhcp
RUN cp /usr/sbin/dhcpd /runtime/usr/sbin/
RUN cp -r /etc/dhcp/* /runtime/etc/dhcp/
RUN ldd /usr/sbin/dhcpd | awk '{if(match($3,"/")) print $3}' | xargs -I '{}' cp -v '{}' /runtime/lib64/
RUN cp /lib64/ld-linux-x86-64.so.2 /runtime/lib64/
COPY entrypoint.sh /runtime/entrypoint.sh
RUN chmod +x /runtime/entrypoint.sh


FROM alpine AS runner

RUN mkdir -p /usr/sbin /lib64 /etc/dhcp /var/lib/dhcpd

WORKDIR /app

COPY --from=builder /runtime/usr/sbin/dhcpd /usr/sbin/dhcpd
COPY --from=builder /runtime/lib64/ /lib64/
COPY --from=builder /runtime/etc/dhcp/ /etc/dhcp/
COPY --from=builder /runtime/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY dhcpd.conf /etc/dhcp/dhcpd.conf

RUN apk add --no-cache bash procps

ENV LD_LIBRARY_PATH=/lib64:/usr/lib64
ENV DHCP_INTERFACE=""



 

EXPOSE 67/udp 68/udp
ENTRYPOINT ["/entrypoint.sh"]
