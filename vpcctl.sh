#!/bin/bash
# vpcctl.sh - Mini VPC with firewall and auto-cleanup
# Usage: sudo ./vpcctl.sh create|delete

set -e

# -----------------------------
# Configurable variables
# -----------------------------
VPC_BRIDGE="br0"
PUBLIC_NS="ns-public"
PRIVATE_NS="ns-private"
PUB_SUBNET="10.10.1.0/24"
PRI_SUBNET="10.10.2.0/24"
PUB_IP="10.10.1.2/24"
PRI_IP="10.10.2.2/24"
BRIDGE_PUB_IP="10.10.1.1/24"
HOST_IF="enX0"    # Replace with your actual host interface
DNS="8.8.8.8"
FIREWALL_JSON="./firewall.json"

# -----------------------------
# Apply firewall rules per namespace
# -----------------------------
apply_firewall() {
    local ns=$1
    echo "[*] Applying firewall rules for $ns"

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

        proto_flag=""
        port_flag=""
        [[ "$proto" != "all" ]] && proto_flag="-p $proto"
        [[ "$port" -ne 0 ]] && port_flag="--dport $port"

        [[ "$action" == "allow" ]] && act_flag="-j ACCEPT" || act_flag="-j DROP"

        ip netns exec $ns iptables -A INPUT $proto_flag $port_flag $act_flag
    done

    # Egress rules
    jq -c ".subnets[\"$ns\"].egress[]" $FIREWALL_JSON | while read rule; do
        port=$(echo $rule | jq '.port')
        proto=$(echo $rule | jq -r '.protocol')
        action=$(echo $rule | jq -r '.action')

        proto_flag=""
        port_flag=""
        [[ "$proto" != "all" ]] && proto_flag="-p $proto"
        [[ "$port" -ne 0 ]] && port_flag="--dport $port"

        [[ "$action" == "allow" ]] && act_flag="-j ACCEPT" || act_flag="-j DROP"

        ip netns exec $ns iptables -A OUTPUT $proto_flag $port_flag $act_flag
    done
}

# -----------------------------
# Create VPC
# -----------------------------
create() {
    echo "=== Creating mini-VPC ==="

    # --- AUTO CLEANUP FIRST ---
    echo "[*] Cleaning any leftover resources..."
    ip netns del $PUBLIC_NS 2>/dev/null || true
    ip netns del $PRIVATE_NS 2>/dev/null || true
    ip link del veth-public 2>/dev/null || true
    ip link del veth-private 2>/dev/null || true
    ip link set $VPC_BRIDGE down 2>/dev/null || true
    ip link del $VPC_BRIDGE type bridge 2>/dev/null || true
    ip addr flush dev $VPC_BRIDGE 2>/dev/null || true

    # 1. Create bridge and assign IP
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

    # 4. Assign IP addresses inside namespaces
    ip netns exec $PUBLIC_NS ip addr add $PUB_IP dev veth-public
    ip netns exec $PRIVATE_NS ip addr add $PRI_IP dev veth-private

    # 5. Bring up interfaces
    ip netns exec $PUBLIC_NS ip link set veth-public up
    ip netns exec $PRIVATE_NS ip link set veth-private up
    ip netns exec $PUBLIC_NS ip link set lo up
    ip netns exec $PRIVATE_NS ip link set lo up

    # 6. Set default routes (after bridge and IP are up)
    ip netns exec $PUBLIC_NS ip route add default via 10.10.1.1 || true
    ip netns exec $PRIVATE_NS ip route add default via 10.10.1.1 || true

    # 7. Enable NAT for public subnet
    sysctl -w net.ipv4.ip_forward=1
    iptables -t nat -A POSTROUTING -s $PUB_SUBNET -o $HOST_IF -j MASQUERADE
    iptables -P FORWARD ACCEPT

    # 8. Configure DNS for public namespace
    mkdir -p /etc/netns/$PUBLIC_NS
    echo "nameserver $DNS" > /etc/netns/$PUBLIC_NS/resolv.conf

    # 9. Apply firewall rules
    apply_firewall $PUBLIC_NS
    apply_firewall $PRIVATE_NS

    echo "=== Mini-VPC created! ==="
}

# -----------------------------
# Delete VPC
# -----------------------------
delete() {
    echo "=== Deleting mini-VPC ==="

    # Flush NAT rule
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

    echo "=== Mini-VPC deleted ==="
}

# -----------------------------
# Main
# -----------------------------
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
