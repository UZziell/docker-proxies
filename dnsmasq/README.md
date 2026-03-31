## dnsmasq

Since DNS tunneling uses port `53` strictly, using dnsmasq allow to run all these tunnels at the same time on one machine.
dnsmasq is configured to act as a DNS Router to route traffic between different DNS tunnels(slipstream-rust, dnstt, noizDNS, MasterDnsVPN) based FQDN of the tunnel. 

### HOW TO USE
Copy `dnsmasq.conf.example` to `dnsmasq.conf`. Based on your setup change the `domain` and `port` in the `Upstream Rules` section. Feel free to add new rules or delete the existing ones.

Rule syntax: 
```
server=/DOMAIN/UPSTREAM_ADDRESS#UPSTREAM_PORT
``` 

Rule example:
```
server=/t.example.com/127.0.0.1#5353`
```
In this example, all incoming queries to `t.example.com` and all it's subdomains, is forwarded to `127.0.0.1:5353`


**Note:** Uncomment `log-queries` and `log-debug` to enable debug logging for troubleshooting