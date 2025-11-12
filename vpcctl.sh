#!/bin/bash
# vpcctl.sh - Mini VPC with firewall
# Usage: sudo ./vpcctl.sh create|delete

set -e

# Configurable variables
VPC_BRIDGE="br0"
PUBLIC_NS="ns-public"
PRIVATE_NS="ns-private"
PUB_SUBNET="10.10.1.0/24"
PRI_SUBNET="10.10.2.0/24"
PUB_IP="10.10.1.2/24"
PRI_IP="10.10.2.2/24"
BRIDGE_PUB_IP="10.10.1.1/24"
HOST_IF="enX0"   # Replace with your actual host interface
DNS="8.8.8.8"
FIREWALL_JSON="./firewall.json"

apply_firewall() {
    local ns=$1
    echo "Applying firewall rules for $ns"

    # Flush previous rules
    ip netns exec $ns iptables -F
    ip netns exec $ns iptables -X
    ip netns exec $ns iptables -P INPUT ACCEPT
    ip netns exec $ns iptables -P OUTPUT ACCEPT
    ip netns exec $ns iptables -P FORWARD ACCEPT

    # Ingress rules
    jq -c ".subnets[\"$ns\"].ingress[]" $FIREWALL_JSON | while read rule; do
        port=$(echo $rule | jq '.port')
        proto=$(echo $rule | jq -r '.protocol')
        action=$(echo $rule | jq -r '.action')
        if [ "$proto" = "all" ]; then
            proto=""
        else
            proto="-p $proto"
        fi
        if [ "$port" -ne 0 ]; then
            port="-m $proto --dport $port"
        else
            port=""
        fi
        if [ "$action" = "allow" ]; then
            action="-j ACCEPT"
        else
            action="-j DROP"
        fi
        ip netns exec $ns iptables -A INPUT $proto $port $action
    done

    # Egress rules
    jq -c ".subnets[\"$ns\"].egress[]" $FIREWALL_JSON | while read rule; do
        port=$(echo $rule | jq '.port')
        proto=$(echo $rule | jq -r '.protocol')
        action=$(echo $rule | jq -r '.action')
        if [ "$proto" = "all" ]; then
            proto=""
        else
            proto="-p $proto"
        fi
        if [ "$port" -ne 0 ]; then
            port="-m $proto --dport $port"
        else
            port=""
        fi
        if [ "$action" = "allow" ]; then
            action="-j ACCEPT"
        else
            action="-j DROP"
        fi
        ip netns exec $ns iptables -A OUTPUT $proto $port $action
    done
}

create() {
    echo "=== Creating mini-VPC with firewall ==="

    # 1. Create bridge
    ip link add name $VPC_BRIDGE type bridge || true
    ip addr add $BRIDGE_PUB_IP dev $VPC_BRIDGE || true
    ip link set $VPC_BRIDGE up

    # 2. Create namespaces
    ip netns add $PUBLIC_NS || true
    ip netns add $PRIVATE_NS || true

    # 3. Create veth pairs
    ip link add veth-public type veth peer name veth-public-br
    ip link add veth-private type veth peer name veth-private-br

    # Attach bridge ends
    ip link set veth-public-br master $VPC_BRIDGE
    ip link set veth-private-br master $VPC_BRIDGE
    ip link set veth-public-br up
    ip link set veth-private-br up

    # Move namespace ends
    ip link set veth-public netns $PUBLIC_NS
    ip link set veth-private netns $PRIVATE_NS

    # 4. Assign IP addresses
    ip netns exec $PUBLIC_NS ip addr add $PUB_IP dev veth-public
    ip netns exec $PRIVATE_NS ip addr add $PRI_IP dev veth-private

    # Bring interfaces up
    ip netns exec $PUBLIC_NS ip link set veth-public up
    ip netns exec $PRIVATE_NS ip link set veth-private up
    ip netns exec $PUBLIC_NS ip link set lo up
    ip netns exec $PRIVATE_NS ip link set lo up

    # 5. Set default routes
    ip netns exec $PUBLIC_NS ip route add default via 10.10.1.1
    ip netns exec $PRIVATE_NS ip route add default via 10.10.1.1

    # 6. Enable NAT for public subnet
    sysctl -w net.ipv4.ip_forward=1
    iptables -t nat -A POSTROUTING -s $PUB_SUBNET -o $HOST_IF -j MASQUERADE
    iptables -P FORWARD ACCEPT

    # 7. Configure DNS for public namespace
    mkdir -p /etc/netns/$PUBLIC_NS
    echo "nameserver $DNS" > /etc/netns/$PUBLIC_NS/resolv.conf

    # 8. Apply firewall rules
    apply_firewall $PUBLIC_NS
    apply_firewall $PRIVATE_NS

    echo "Mini-VPC created with firewall!"
}

delete() {
    echo "=== Deleting mini-VPC ==="

    # Flush NAT rules
    iptables -t nat -D POSTROUTING -s $PUB_SUBNET -o $HOST_IF -j MASQUERADE 2>/dev/null || true

    # Delete namespaces
    ip netns del $PUBLIC_NS 2>/dev/null || true
    ip netns del $PRIVATE_NS 2>/dev/null || true

    # Delete veth pairs
    ip link del veth-public 2>/dev/null || true
    ip link del veth-private 2>/dev/null || true

    # Delete bridge
    ip link set $VPC_BRIDGE down 2>/dev/null || true
    ip link del $VPC_BRIDGE type bridge 2>/dev/null || true

    echo "Mini-VPC deleted!"
}

case "$1" in
    create)
        create
        ;;
    delete)
        delete
        ;;
    *)
        echo "Usage: sudo $0 create|delete"
        exit 1
        ;;
esac
