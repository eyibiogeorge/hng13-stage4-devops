Mini-VPC on Linux

Simulate a Virtual Private Cloud (VPC) on a single Linux host using network namespaces, veth pairs, Linux bridges, routing, NAT, and iptables.
This project demonstrates public/private subnets, NAT gateway behavior, firewall rules, and VPC isolation.

Features

Create a mini VPC with public and private subnets.

Routing between subnets via a Linux bridge.

NAT gateway for public subnet to access the internet.

Firewall rules per subnet using iptables.

Automated creation, testing, and cleanup via vpcctl.sh.

Idempotent: safely re-run without breaking existing resources.

Requirements

Linux host (tested on Ubuntu 24.04+)

Root or sudo privileges

Native Linux networking tools: ip, iptables, bridge

Bash

Usage

Clone repository:

git clone <your-repo-url>
cd mini-vpc
chmod +x vpcctl.sh

Create Mini-VPC
sudo ./vpcctl.sh create


Output:

=== Creating mini-VPC ===
[*] Cleaning leftover resources...
[*] Cleanup complete.
[*] Enabling IP forwarding...
[*] Creating bridge br0...
[*] Creating namespaces...
[*] Configuring ns-public...
[*] Configuring ns-private...
[*] Setting up NAT for public subnet...
[*] Applying firewall rules for ns-public...
[*] Applying firewall rules for ns-private...
=== Mini-VPC created! ===

Test Connectivity

Internal subnet communication:

sudo ip netns exec ns-public ping -c 2 10.10.2.2
sudo ip netns exec ns-private ping -c 2 10.10.1.2


Internet access:

sudo ip netns exec ns-public ping -c 2 8.8.8.8
sudo ip netns exec ns-public curl -I http://example.com
sudo ip netns exec ns-private ping -c 2 8.8.8.8   # Should fail


Check interfaces:

ip link show br0
ip link show veth-br-public
ip link show veth-br-private

Firewall Rules

ns-public allows outbound HTTP/HTTPS (ports 80, 443).

ns-private is internal-only; outbound blocked.

Rules are defined in the script and applied automatically with iptables.

Clean Up
sudo ./vpcctl.sh delete


Output:

[*] Deleting namespaces and veth pairs...
[*] Deleting bridge br0...
[*] Cleanup complete.

Architecture Diagram
             +-------------------+
             |       br0         |
             +-------------------+
              |                 |
        veth-br-public      veth-br-private
              |                 |
         ns-public           ns-private
         (10.10.1.0/24)      (10.10.2.0/24)
            | NAT + Internet     | Internal only