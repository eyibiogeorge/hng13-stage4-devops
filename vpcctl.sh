#!/bin/bash
# vpcctl.sh - Mini VPC CLI for Linux

set -e

VPC_NAME="mini-vpc"
BRIDGE="br0"
PUBLIC_NS="ns-public"
PRIVATE_NS="ns-private"
PUBLIC_SUBNET="10.10.1.0/24"
PRIVATE_SUBNET="10.10.2.0/24"
PUBLIC_GW="10.10.1.1"
PRIVATE_GW="10.10.2.1"
INT_IF="enX0"  # Replace with your host interface

# Firewall rules (example JSON-like structure)
declare -A FW_PUBLIC=( ["allow"]="tcp:80 tcp:443" ["deny"]="tcp:22" )
declare -A FW_PRIVATE=( ["allow"]="" ["deny"]="tcp:80 tcp:443 tcp:22" )

# Auto-cleanup
cleanup() {
    echo "[*] Cleaning leftover resources..."
    ip netns del $PUBLIC_NS 2>/dev/null || true
    ip netns del $PRIVATE_NS 2>/dev/null || true
    ip link del veth-br-public 2>/dev/null || true
    ip link del veth-br-private 2>/dev/null || true
    ip link del $BRIDGE 2>/dev/null || true
    iptables -t nat -F
    echo "[*] Cleanup complete."
}

create_vpc() {
    echo "=== Creating mini-VPC ==="
    cleanup

    # Enable IP forwarding
    echo "[*] Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1

    # Create bridge
    echo "[*] Creating bridge $BRIDGE..."
    ip link add name $BRIDGE type bridge || true
    ip addr add $PUBLIC_GW/24 dev $BRIDGE || true
    ip addr add $PRIVATE_GW/24 dev $BRIDGE || true
    ip link set $BRIDGE up

    # Create namespaces
    echo "[*] Creating namespaces..."
    ip netns add $PUBLIC_NS || true
    ip netns add $PRIVATE_NS || true

    # Create veth pairs
    ip link add veth-public type veth peer name veth-br-public
    ip link add veth-private type veth peer name veth-br-private

    # Attach veths to namespaces
    ip link set veth-public netns $PUBLIC_NS
    ip link set veth-private netns $PRIVATE_NS

    # Attach veths to bridge
    ip link set veth-br-public master $BRIDGE
    ip link set veth-br-private master $BRIDGE
    ip link set veth-br-public up
    ip link set veth-br-private up

    # Configure namespace interfaces
    echo "[*] Configuring $PUBLIC_NS..."
    ip netns exec $PUBLIC_NS ip addr add 10.10.1.2/24 dev veth-public
    ip netns exec $PUBLIC_NS ip link set veth-public up
    ip netns exec $PUBLIC_NS ip link set lo up
    ip netns exec $PUBLIC_NS ip route add default via $PUBLIC_GW

    echo "[*] Configuring $PRIVATE_NS..."
    ip netns exec $PRIVATE_NS ip addr add 10.10.2.2/24 dev veth-private
    ip netns exec $PRIVATE_NS ip link set veth-private up
    ip netns exec $PRIVATE_NS ip link set lo up
    ip netns exec $PRIVATE_NS ip route add default via $PRIVATE_GW

    # Setup NAT for public subnet
    echo "[*] Setting up NAT for public subnet..."
    iptables -t nat -A POSTROUTING -s $PUBLIC_SUBNET -o $INT_IF -j MASQUERADE

    # Optional: firewall rules
    echo "[*] Applying firewall rules for $PUBLIC_NS..."
    for rule in ${FW_PUBLIC["allow"]}; do
        proto=${rule%:*}
        port=${rule#*:}
        ip netns exec $PUBLIC_NS iptables -A INPUT -p $proto --dport $port -j ACCEPT
    done
    for rule in ${FW_PUBLIC["deny"]}; do
        proto=${rule%:*}
        port=${rule#*:}
        ip netns exec $PUBLIC_NS iptables -A INPUT -p $proto --dport $port -j DROP
    done

    echo "[*] Applying firewall rules for $PRIVATE_NS..."
    for rule in ${FW_PRIVATE["allow"]}; do
        proto=${rule%:*}
        port=${rule#*:}
        ip netns exec $PRIVATE_NS iptables -A INPUT -p $proto --dport $port -j ACCEPT
    done
    for rule in ${FW_PRIVATE["deny"]}; do
        proto=${rule%:*}
        port=${rule#*:}
        ip netns exec $PRIVATE_NS iptables -A INPUT -p $proto --dport $port -j DROP
    done

    echo "=== Mini-VPC created! ==="
}

delete_vpc() {
    echo "=== Deleting mini-VPC ==="
    cleanup
    echo "=== Mini-VPC deleted! ==="
}

status_vpc() {
    echo "=== Mini-VPC Status ==="
    ip netns list
    ip link show $BRIDGE || echo "$BRIDGE does not exist"
}

case "$1" in
    create)
        create_vpc
        ;;
    delete)
        delete_vpc
        ;;
    status)
        status_vpc
        ;;
    *)
        echo "Usage: $0 {create|delete|status}"
        exit 1
        ;;
esac

