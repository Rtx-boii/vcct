$TTL    86400
@       IN      SOA     server.vcct.com. root.vcct.com. (
                                2025041401  ; Serial
                                3600        ; Refresh
                                900         ; Retry
                                604800      ; Expire
                                86400       ; Minimum TTL
                                )
@       IN      NS      server.vcct.com.
20      IN      PTR     server.vcct.com.
132	IN	PTR	csne.vcct.com.
