FROM rockylinux:9 AS builder

WORKDIR /build

RUN dnf install -y bind bind-utils && dnf clean all
RUN mkdir -p /runtime/usr/sbin /runtime/lib64 /runtime/etc/named /runtime/var/named /runtime/run/named /runtime/var/log/named /runtime/etc/crypto-policies/back-ends

RUN rndc-confgen -a -c /runtime/etc/rndc.key

RUN cp /usr/sbin/named /usr/sbin/rndc /runtime/usr/sbin/
RUN cp -r /etc/named.conf /runtime/etc/named/
RUN cp -r /etc/named.* /runtime/etc/named/ || true
RUN cp -r /var/named/* /runtime/var/named/ || true
RUN cp /etc/named.root.key /runtime/etc/
RUN cp /etc/named.rfc1912.zones /runtime/etc/
RUN cp /etc/crypto-policies/back-ends/bind.config /runtime/etc/crypto-policies/back-ends/ || true
RUN ldd /usr/sbin/named /usr/sbin/rndc | awk '{if(match($3,"/")) print $3}' | xargs -I '{}' cp -v '{}' /runtime/lib64/
RUN cp /lib64/ld-linux-x86-64.so.2 /runtime/lib64/

COPY entrypoint.sh /runtime/entrypoint.sh
RUN chmod +x /runtime/entrypoint.sh



FROM alpine AS runner

WORKDIR /app


RUN mkdir -p /usr/sbin /lib64 /etc/named /var/named /var/log/named /etc/crypto-policies/back-ends /run/named

COPY --from=builder /runtime/ /

RUN apk add --no-cache bash bind-tools

COPY named.conf /etc/named.conf
COPY forward.vcct.com /var/named/forward.vcct.com
COPY reverse.vcct.com /var/named/reverse.vcct.com


RUN adduser -D -u 1000 named \
    && chown -R named:named /var/named /var/log/named /run/named \
    && chown named:named /etc/named.conf /etc/named.rfc1912.zones /etc/named.root.key /etc/rndc.key \
    && chmod -R 770 /var/named /var/log/named /run/named \
    && chmod 644 /etc/named.rfc1912.zones /etc/named.root.key \
    && chmod 640 /etc/named.conf /var/named/forward.vcct.com /var/named/reverse.vcct.com \
    && chmod 600 /etc/rndc.key



ENV DNS_OPTIONS="-u named -g"
ENV LD_LIBRARY_PATH=/lib64:/usr/lib64

#health check



HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD dig @localhost || exit 1

EXPOSE 53/tcp
EXPOSE 53/udp

ENTRYPOINT ["/entrypoint.sh"]
