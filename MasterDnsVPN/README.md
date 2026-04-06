# MasterDnsVPN
Original repository: [https://github.com/masterking32/MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN)

### Preparing
Before running configuration files for both client and server should be downloaded and placed in the current directory.

#### Server
```bash
curl -sSfL https://raw.githubusercontent.com/masterking32/MasterDnsVPN/refs/heads/main/server_config.toml.simple --output server_config.toml;
```
Make the minimum configuration changes according to
[Server configuration checklist](https://github.com/masterking32/MasterDnsVPN#section-33-quick-server-checklist-%EF%B8%8F)

#### Client
```bash
curl -sSfL https://raw.githubusercontent.com/masterking32/MasterDnsVPN/refs/heads/main/client_config.toml.simple --output client_config.toml;
```
Make the minimum configuration changes according to
[Client configuration checklist](https://github.com/masterking32/MasterDnsVPN#section-32-quick-client-checklist-)

In addition to configuration file, [as per the the documentation](https://github.com/masterking32/MasterDnsVPN#section-31-important-project-files-), client needs a `client_resolvers.txt` that should be placed in the `data/client_resolvers.txt` directory.


### Running
#### Server
```bash
docker compose up --build -d server
```
When server is started for the first time, an encryption key is generated and saved to `data/encrypt_key.txt` file that should be used in the `client_config.toml` for `ENCRYPTION_KEY`

#### Client
```bash
docker compose up --build -d client
```