$TTL    86400
@       IN      SOA     server.vcct.com. root.vcct.com. (
                                2025041401  ; Serial
                                3600        ; Refresh
                                900         ; Retry
                                604800      ; Expire
                                86400       ; minimum
                                )
@                                 IN      NS      server.vcct.com.
@                                 IN      A       192.168.8.20
server                            IN      A       192.168.8.20
csne			          IN	  A 	  192.168.8.132
