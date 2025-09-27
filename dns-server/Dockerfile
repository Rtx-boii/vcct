FROM rockylinux:9 AS builder

WORKDIR /build

RUN dnf install -y bind bind-utils && dnf clean all
RUN mkdir -p /runtime/usr/sbin /runtime/lib64 /runtime/etc/named /runtime/var/named /runtime/var/log/named

RUN cp /usr/sbin/named /usr/sbin/rndc /runtime/usr/sbin/
RUN cp -r /etc/named.conf /runtime/etc/named/
RUN cp -r /etc/named.* /runtime/etc/named/ || true
RUN cp -r /var/named/* /runtime/var/named/ || true
RUN cp /etc/named.root.key /runtime/etc/
RUN ldd /usr/sbin/named /usr/sbin/rndc | awk '{if(match($3,"/")) print $3}' | xargs -I '{}' cp -v '{}' /runtime/lib64/
RUN cp /lib64/ld-linux-x86-64.so.2 /runtime/lib64/

COPY entrypoint.sh /runtime/entrypoint.sh
RUN chmod +x /runtime/entrypoint.sh

FROM alpine AS runner

WORKDIR /app

RUN mkdir -p /usr/sbin /lib64 /etc/named /var/named /var/log/named /etc/crypto-policies/back-ends

COPY --from=builder /runtime/ /
COPY --from=builder /etc/crypto-policies/back-ends/bind.config /etc/crypto-policies/back-ends/bind.config
COPY --from=builder /etc/named.rfc1912.zones /etc/named.rfc1912.zones
RUN chmod +x /entrypoint.sh
RUN apk add --no-cache bash

COPY named.conf /etc/named.conf
COPY forward.vcct.com /var/named/forward.vcct.com
COPY reverse.vcct.com /var/named/reverse.vcct.com

RUN adduser -D -u 1000 named \
    && chown -R named:named /var/named /var/log/named /etc/named  /etc/named.root.key \
    && chmod -R 750 /var/named /var/log/named \
    && chmod 644 /etc/named.rfc1912.zones  /etc/named.root.key \
    && chmod 640 /var/named/forward.vcct.com /var/named/reverse.vcct.com

USER named

ENV DNS_OPTIONS="-g"
ENV LD_LIBRARY_PATH=/lib64:/usr/lib64

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/entrypoint.sh"]
