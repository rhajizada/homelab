[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ${server_private_key}

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

[Peer]
PublicKey = ${client_public_key}
AllowedIPs = 10.8.0.2/32
