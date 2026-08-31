#!/bin/sh
set -eu

###############################################################################
# OPENWRT + SURFSHARK WIREGUARD + YOUTUBE POLICY-BASED ROUTING
#
# PURPOSE
# Route selected YouTube-related traffic through a Surfshark WireGuard tunnel
# while leaving normal Internet traffic on the router's regular WAN connection.
#
# FILL THESE IN FIRST
#
# 1) WG_PRIVATE_KEY
#    Your own WireGuard private key from Surfshark manual setup.
#
# 2) WG_ADDRESS
#    Your WireGuard interface address from Surfshark.
#    Example format: 10.14.0.2/16
#
# 3) SURFSHARK_SERVER_PUBLIC_KEY
#    The public key of the Surfshark server/location you selected.
#
# 4) SURFSHARK_ENDPOINT_HOST
#    The Surfshark server hostname.
#    Example format: xx-xxx.prod.surfshark.com
#
# 5) SURFSHARK_ENDPOINT_PORT
#    Usually 51820.
#
# OPTIONAL
# 6) PBR_POLICY_NAME
#    Friendly policy label.
#
# AUTO-DETECTED FROM THE ROUTER
# - LAN device
# - LAN IPv4 subnet and prefix length
# - WAN/uplink interface
# - Package manager (apk or opkg)
#
# SECURITY
# - Never share your WireGuard private key.
# - Each user should use their own WireGuard key pair and Surfshark details.
#
# SCOPE
# - This script configures a Surfshark WireGuard interface, firewall forwarding,
#   and OpenWrt PBR for selected YouTube-related destinations.
# - It does not intentionally modify unrelated services.
###############################################################################

### ===== FILL THESE VALUES IN =====

WG_PRIVATE_KEY='PASTE_YOUR_WIREGUARD_PRIVATE_KEY_HERE'

WG_ADDRESS='PASTE_YOUR_WIREGUARD_ADDRESS_HERE'

SURFSHARK_SERVER_PUBLIC_KEY='PASTE_SURFSHARK_SERVER_PUBLIC_KEY_HERE'

SURFSHARK_ENDPOINT_HOST='PASTE_SURFSHARK_SERVER_HOSTNAME_HERE'

SURFSHARK_ENDPOINT_PORT='51820'

PBR_POLICY_NAME='YouTube via Surfshark'

### ===== STOP EDITING HERE =====


die() {
    echo "ERROR: $*" >&2
    exit 1
}

need_value() {
    val="$1"
    placeholder="$2"
    label="$3"

    [ -n "$val" ] || die "$label is empty."
    [ "$val" != "$placeholder" ] || die "Set $label first."
}

need_value "$WG_PRIVATE_KEY" \
    'PASTE_YOUR_WIREGUARD_PRIVATE_KEY_HERE' \
    'WG_PRIVATE_KEY'

need_value "$WG_ADDRESS" \
    'PASTE_YOUR_WIREGUARD_ADDRESS_HERE' \
    'WG_ADDRESS'

need_value "$SURFSHARK_SERVER_PUBLIC_KEY" \
    'PASTE_SURFSHARK_SERVER_PUBLIC_KEY_HERE' \
    'SURFSHARK_SERVER_PUBLIC_KEY'

need_value "$SURFSHARK_ENDPOINT_HOST" \
    'PASTE_SURFSHARK_SERVER_HOSTNAME_HERE' \
    'SURFSHARK_ENDPOINT_HOST'


echo "========================================================"
echo " OpenWrt + Surfshark + YouTube PBR installer"
echo "========================================================"
echo
echo "User-supplied VPN values:"
echo "  WG address     : $WG_ADDRESS"
echo "  Server host    : $SURFSHARK_ENDPOINT_HOST"
echo "  Server port    : $SURFSHARK_ENDPOINT_PORT"
echo "  Policy name    : $PBR_POLICY_NAME"
echo "  Private key    : [hidden]"
echo "  Server pubkey  : [provided]"
echo

echo "== Detecting router settings =="

LAN_DEVICE="$(uci -q get network.lan.device || true)"
[ -n "$LAN_DEVICE" ] || LAN_DEVICE="$(uci -q get network.lan.ifname || true)"

if [ -z "$LAN_DEVICE" ] && command -v ubus >/dev/null 2>&1; then
    LAN_DEVICE="$(ubus call network.interface.lan status 2>/dev/null \
        | jsonfilter -e '@.l3_device' 2>/dev/null || true)"
fi

[ -n "$LAN_DEVICE" ] || die "Could not determine LAN device."

LAN_SUBNET="$(ip -4 route show dev "$LAN_DEVICE" proto kernel scope link 2>/dev/null \
    | awk '$1 ~ /^[0-9]+\./ {print $1; exit}')"

if [ -z "$LAN_SUBNET" ]; then
    LAN_SUBNET="$(ip -4 route show dev "$LAN_DEVICE" 2>/dev/null \
        | awk '$1 ~ /^[0-9]+\./ && $1 ~ /\// {print $1; exit}')"
fi

[ -n "$LAN_SUBNET" ] || die "Could not determine LAN IPv4 subnet from device $LAN_DEVICE."

WAN_IFACE='wan'
if ! uci -q get network.wan >/dev/null 2>&1; then
    WAN_IFACE="$(ip -4 route show default \
        | awk '$1=="default" && $0 !~ /surfshark/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
fi
[ -n "$WAN_IFACE" ] || WAN_IFACE='wan'

echo "Detected:"
echo "  LAN device     : $LAN_DEVICE"
echo "  LAN subnet     : $LAN_SUBNET"
echo "  WAN/uplink     : $WAN_IFACE"
echo

echo "== Checking Surfshark endpoint DNS =="

RESOLVED_ENDPOINT="$(nslookup "$SURFSHARK_ENDPOINT_HOST" 127.0.0.1 2>/dev/null \
    | awk '/^Address: / {print $2}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -v '^127\.' \
    | grep -v '^0\.0\.0\.0$' \
    | tail -1 || true)"

if [ -z "$RESOLVED_ENDPOINT" ]; then
    echo "WARNING: $SURFSHARK_ENDPOINT_HOST did not resolve to a usable IPv4 address."
    echo "Check the router's DNS configuration before continuing if the tunnel does not connect."
else
    echo "$SURFSHARK_ENDPOINT_HOST -> $RESOLVED_ENDPOINT"
fi

echo
echo "== Installing required packages =="

if command -v apk >/dev/null 2>&1; then
    apk -U add kmod-wireguard wireguard-tools luci-proto-wireguard pbr luci-app-pbr
elif command -v opkg >/dev/null 2>&1; then
    opkg update
    opkg install kmod-wireguard wireguard-tools luci-proto-wireguard pbr luci-app-pbr
else
    die "Neither apk nor opkg was found."
fi

echo
echo "== Configuring Surfshark WireGuard =="

uci -q delete network.surfshark
uci set network.surfshark='interface'
uci set network.surfshark.proto='wireguard'
uci set network.surfshark.private_key="$WG_PRIVATE_KEY"
uci add_list network.surfshark.addresses="$WG_ADDRESS"
uci set network.surfshark.metric='5000'

uci -q delete network.surfshark_peer
uci set network.surfshark_peer='wireguard_surfshark'
uci set network.surfshark_peer.public_key="$SURFSHARK_SERVER_PUBLIC_KEY"
uci set network.surfshark_peer.endpoint_host="$SURFSHARK_ENDPOINT_HOST"
uci set network.surfshark_peer.endpoint_port="$SURFSHARK_ENDPOINT_PORT"
uci set network.surfshark_peer.persistent_keepalive='25'
uci set network.surfshark_peer.route_allowed_ips='1'
uci add_list network.surfshark_peer.allowed_ips='0.0.0.0/0'

uci commit network

echo
echo "== Configuring firewall =="

for s in $(uci show firewall 2>/dev/null | sed -n "s/^\(firewall\.[^.]*\)\.name='surfshark'$/\1/p"); do
    uci -q delete "$s"
done

for s in $(uci show firewall 2>/dev/null | sed -n "s/^\(firewall\.[^.]*\)\.dest='surfshark'$/\1/p"); do
    uci -q delete "$s"
done

FW_ZONE="$(uci add firewall zone)"
uci set firewall."$FW_ZONE".name='surfshark'
uci add_list firewall."$FW_ZONE".network='surfshark'
uci set firewall."$FW_ZONE".input='REJECT'
uci set firewall."$FW_ZONE".output='ACCEPT'
uci set firewall."$FW_ZONE".forward='REJECT'
uci set firewall."$FW_ZONE".masq='1'
uci set firewall."$FW_ZONE".mtu_fix='1'

FW_FWD="$(uci add firewall forwarding)"
uci set firewall."$FW_FWD".src='lan'
uci set firewall."$FW_FWD".dest='surfshark'

uci commit firewall

echo
echo "== Configuring PBR =="

uci set pbr.config.enabled='1'
uci set pbr.config.strict_enforcement='1'
uci set pbr.config.resolver_set='dnsmasq.nftset'
uci set pbr.config.ipv6_enabled='0'
uci set pbr.config.uplink_interface="$WAN_IFACE"

uci -q delete pbr.youtube_surfshark
uci set pbr.youtube_surfshark='policy'
uci set pbr.youtube_surfshark.name="$PBR_POLICY_NAME"
uci set pbr.youtube_surfshark.interface='surfshark'
uci set pbr.youtube_surfshark.proto='all'
uci set pbr.youtube_surfshark.src_addr="$LAN_SUBNET"
uci set pbr.youtube_surfshark.enabled='1'

# YouTube and selected supporting endpoints.
# Generic roots such as google.com are intentionally excluded so unrelated
# Google traffic is less likely to follow this policy.
uci set pbr.youtube_surfshark.dest_addr='youtube.com youtu.be yt.be youtube-nocookie.com youtubekids.com googlevideo.com ytimg.com youtubei.googleapis.com youtube.googleapis.com youtubeembeddedplayer.googleapis.com youtube-ui.l.google.com youtube.l.google.com ytimg.l.google.com wide-youtube.l.google.com yt3.ggpht.com yt3.googleusercontent.com accounts.google.com www.gstatic.com ssl.gstatic.com fonts.gstatic.com lh3.googleusercontent.com lh5.googleusercontent.com lh6.googleusercontent.com www.googleadservices.com googleads.g.doubleclick.net pagead2.googlesyndication.com tpc.googlesyndication.com ad.doubleclick.net ade.googlesyndication.com ifconfig.me'

uci commit pbr

echo
echo "== Applying configuration =="

ifdown surfshark 2>/dev/null || true
sleep 1
/etc/init.d/firewall restart
ifup surfshark
sleep 5
/etc/init.d/pbr restart
sleep 3

echo
echo "===== FINAL SETTINGS ====="
echo "LAN device     : $LAN_DEVICE"
echo "LAN subnet     : $LAN_SUBNET"
echo "PBR uplink     : $WAN_IFACE"
echo "VPN endpoint   : $SURFSHARK_ENDPOINT_HOST:$SURFSHARK_ENDPOINT_PORT"

echo
echo "===== WIREGUARD ====="
wg show surfshark || true

echo
echo "===== DEFAULT ROUTES ====="
ip route show default || true

echo
echo "===== PBR ====="
/etc/init.d/pbr status || true

echo
echo "===== PBR SOURCE ====="
uci -q get pbr.youtube_surfshark.src_addr || true

echo
echo "Setup complete."
echo
echo "Suggested tests from a LAN device:"
echo "  1. Open YouTube and play several videos."
echo "  2. Visit ifconfig.me; it is intentionally included in the test policy."
echo "  3. Visit another IP-check site not in the policy; it should use the normal WAN."
