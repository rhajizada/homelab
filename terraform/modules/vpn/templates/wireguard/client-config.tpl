[Interface]
Address = 10.8.0.2/24
PrivateKey = ${client_private_key}
DNS = ${cluster_network_gateway}

[Peer]
PublicKey = ${server_public_key}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${server_ip}:51820
PersistentKeepalive = 25
