

**Cerbot** is also included to provide LetsEncrypt SSL/TLS certificates


# Docker Proxies

A curated collection of Docker Compose configurations designed for the easy deployment of various censorship bypass services.

## Included Proxies
Below are the supported proxies, linked to their original authors or official repositories:

* Xray/Sing-box Panels
    * [3x-ui](https://github.com/MHSanaei/3x-ui) – Xray core panel
    * [s-ui](https://github.com/alireza0/s-ui) – An advanced Web Panel • Built for SagerNet/Sing-Box
    * [x-ui](https://github.com/alireza0/x-ui) – Xray core panel

* DNS Tunnels
    * [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) - Dnsmasq provides network infrastructure for small networks **(In this project it's used as a DNS router for DNS based tunnels)**
    * [dnstt](https://www.bamsoftware.com/software/dnstt/) – DNS tunnel that can use DNS over HTTPS (DoH) and DNS over TLS (DoT) resolvers. 
    * [MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) - Advanced DNS tunneling VPN for censorship bypass, optimized beyond DNSTT and SlipStream with low-overhead ARQ, SOCKS5 multiplexing, resolver load balancing, and high packet-loss stability.
    * [slipstream-rust](https://github.com/Mygod/slipstream-rust) - High-performance multi-path covert channel over DNS in Rust with vibe coding
    * [vaydns](https://github.com/net2share/vaydns) - Userspace DNS tunnel with support for DoH, DoT, and plaintext UDP

* [3proxy](https://github.com/tarampampam/3proxy-docker) – Tiny free proxy server
* [hysteria](https://github.com/apernet/hysteria) – powerful, lightning fast and censorship resistant proxy.
* [naiveproxy](https://github.com/klzgrad/naiveproxy) – NaïveProxy uses Chromium's network stack to camouflage traffic with strong censorship resistence 
* [pingtunnel](https://github.com/esrrhs/pingtunnel) – sends TCP/UDP traffic over ICMP 
* [sing-box](https://github.com/SagerNet/sing-box) – The universal proxy platform

* [**Certbot**](https://github.com/certbot/certbot) is also included to facilitate the automated generation and renewal of Let's Encrypt SSL/TLS certificates used by various proxies

## Requirements
*   **Docker** version 27.5.1 or higher.

## Usage

Most proxies can be deployed using the following steps. For proxies requiring additional configuration, please refer to the specific README.md within their respective directories.

1.  **Navigate** to the specific proxy directory:
    ```bash
    cd <proxy-name>
    ```

2.  **Set up configuration**:
    Copy the example environment file and **update the variables with your configuration**:
    ```bash
    cp .env.example .env
    ```

3.  **Start the service**:
    Start the service. If it's a client/server service like most dns tunnels, specify the sevice by adding `client` or `server` to the end of the command
    ```bash
    docker compose up -d [server/client]
    ```
    For services that does not have a ready to use image(**dnstt, MasterDnsVPN, and vaydns**) `--build` option should be added to this command for first time and updates
    ```bash
    docker compose up --build -d [server/client]
    ```