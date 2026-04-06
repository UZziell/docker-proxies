## dnsmasq

Since DNS tunneling uses port `53` strictly, using dnsmasq allow to run all these tunnels at the same time on one machine.
dnsmasq is configured to act as a DNS Router to route traffic between different DNS tunnels(**slipstream-rust**, **dnstt**, **noizDNS**, **MasterDnsVPN**, and **vaydns**) based FQDN of the tunnel. 

### HOW TO USE
Copy `dnsmasq.conf.example` to `dnsmasq.conf`. Based on your setup change the `domain` and `port` in the `Upstream Rules` section. Feel free to add new rules or delete the existing ones.

The defaults upstream rules are based on the following table:
|      Service     | Port |
|:----------------:|:----:|
|      dnsmasq     |  53  |
|  Slipstream-rust | 5301 |
|       dnstt      | 5302 |
|   MasterDnsVPN   | 5303 |
|      varydns     | 5304 |
| noizDNS(Slipnet) | 5300 |

Rule syntax: 
```
server=/DOMAIN/UPSTREAM_ADDRESS#UPSTREAM_PORT
``` 

Rule example:
```
server=/t.example.com/127.0.0.1#5353`
```
In this example, all incoming queries to `t.example.com` and all it's subdomains, is forwarded to `127.0.0.1:5353`

### Notes
#### Changing Service Ports 
When changing default ports, they should also be changed on their respective service. For example, when changing the default varydns rule from `server=/d.example.com/127.0.0.1#5304` to `server=/d.example.com/127.0.0.1#1234`, the respective `VAYDNS_LISTEN_PORT` value should also be changed to `1234`

#### Troubleshoot
For troubleshooting dnsmasq, uncomment `log-queries` and `log-debug` to enable debug logging