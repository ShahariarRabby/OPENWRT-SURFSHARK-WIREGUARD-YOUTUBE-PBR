# OpenWrt Surfshark WireGuard + YouTube PBR

A small OpenWrt setup script for **selective policy-based routing**.

The goal is simple:

```text
Normal Internet traffic  -> regular WAN
Selected YouTube traffic -> Surfshark WireGuard
```

The script creates a Surfshark WireGuard interface and an OpenWrt PBR policy for selected YouTube-related destinations while keeping the normal WAN route preferred.

## Requirements

You need an OpenWrt router and a Surfshark account with access to **Manual Setup -> WireGuard**.

The script supports OpenWrt systems using either `apk` or `opkg`.

## Fill these values in first

Open:

```text
setup-surfshark-youtube-pbr.sh
```

At the very top, enter the following values from Surfshark:

### `WG_PRIVATE_KEY`

Your own WireGuard private key.

Never publish or share this value.

### `WG_ADDRESS`

The WireGuard interface address supplied by Surfshark.

Example:

```text
10.14.0.2/16
```

### `SURFSHARK_SERVER_PUBLIC_KEY`

The public key shown for the Surfshark server/location you selected.

### `SURFSHARK_ENDPOINT_HOST`

The Surfshark server hostname.

Example format:

```text
xx-xxx.prod.surfshark.com
```

### `SURFSHARK_ENDPOINT_PORT`

Normally:

```text
51820
```

### `PBR_POLICY_NAME`

Optional friendly label for the OpenWrt PBR policy.

## Automatically detected

The script attempts to determine these values directly from OpenWrt:

- LAN device
- LAN IPv4 network
- LAN prefix length
- WAN/uplink interface
- package manager

This means the script does not assume that every router uses the same LAN range.

For example, these are all valid possibilities:

```text
192.168.1.0/24
10.0.0.0/8
172.16.0.0/16
```

## Installation

Copy the script to the OpenWrt router.

Then run:

```sh
chmod 700 setup-surfshark-youtube-pbr.sh
./setup-surfshark-youtube-pbr.sh
```

The script prints the detected LAN subnet and uplink before applying the configuration.

## What the script configures

It creates or replaces:

- `network.surfshark`
- `network.surfshark_peer`
- a `surfshark` firewall zone
- LAN -> Surfshark forwarding
- PBR policy `youtube_surfshark`

It also enables:

- WireGuard persistent keepalive
- Surfshark masquerading
- MTU fixing
- PBR strict enforcement
- `dnsmasq.nftset`
- IPv4 PBR

## Routing design

Surfshark uses:

```text
AllowedIPs = 0.0.0.0/0
```

but the interface receives a high route metric:

```text
5000
```

so the regular WAN default remains preferred.

OpenWrt PBR marks selected destination traffic and sends only those flows through the Surfshark routing table.

## Selected destinations

The policy contains YouTube-native domains and selected supporting Google endpoints commonly involved in YouTube operation.

Generic roots such as:

```text
google.com
```

are intentionally excluded to reduce the chance of unrelated Google traffic following the VPN policy.

`ifconfig.me` is included as a convenient routing test destination.

## Verify

Check WireGuard:

```sh
wg show surfshark
```

Look for a recent handshake.

Check default routes:

```sh
ip route show default
```

The regular WAN should remain preferred.

Check PBR:

```sh
/etc/init.d/pbr status
```

Check the source network detected by the script:

```sh
uci get pbr.youtube_surfshark.src_addr
```

Check policy matches:

```sh
nft list chain inet fw4 pbr_prerouting
```

Check the populated nftset:

```sh
nft list set inet fw4 pbr_surfshark_4_dst_ip_youtube_surfshark
```

## Test routing

From a LAN device:

1. Open YouTube and generate some traffic.
2. Open `ifconfig.me`.
3. Confirm that the test destination reflects the selected Surfshark location.
4. Open another IP-check service that is not part of the policy and confirm it uses the normal WAN address.

## Endpoint DNS troubleshooting

If the Surfshark endpoint hostname does not resolve, test it from the router:

```sh
nslookup YOUR-SURFSHARK-HOSTNAME
```

Also verify that the hostname resolves to a usable public IP address before troubleshooting WireGuard itself.

## General troubleshooting

Immediately after a connectivity problem, capture:

```sh
date

wg show surfshark

ip route show default

ping -c 5 -W 2 1.1.1.1

/etc/init.d/pbr status

logread | grep -Ei 'surfshark|wireguard|pbr|wan|dnsmasq|timeout|fail|error' | tail -n 200
```

This usually helps distinguish between:

- WAN connectivity
- WireGuard endpoint connectivity
- interface restarts
- DNS resolution
- PBR reloads

## Security

Each user should create or register their own WireGuard key pair with Surfshark.

Do not commit a real private key to GitHub.

A good check before committing is:

```sh
grep -R "PrivateKey\|WG_PRIVATE_KEY" .
```

The repository should contain only placeholders, never a live private key.

## Notes

This is a community setup example, not an official Surfshark or OpenWrt project.

Review the script before running it on a production router.
