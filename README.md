# Mini-VPC on Linux

- Simulate a Virtual Private Cloud (VPC) on a single Linux host using network namespaces, veth pairs, Linux bridges, routing, NAT, and iptables.

- This project demonstrates public/private subnets, NAT gateway behavior, firewall rules, and VPC isolation.

## Features

1. Create a mini VPC with public and private subnets.

2. Routing between subnets via a Linux bridge.

3. NAT gateway for public subnet to access the internet.

4. Firewall rules per subnet using iptables.

5. Automated creation, testing, and cleanup via vpcctl.sh.

6. Idempotent: safely re-run without breaking existing resources.

## Requirements

- Linux host (tested on Ubuntu 24.04+)

- Root or sudo privileges

- Native Linux networking tools: ip, iptables, bridge

- Bash

- Usage

Clone repository:
```bash
git clone https://github.com/eyibiogeorge/hng13-stage4-devops.git
cd hng13-stage4-devops
chmod +x vpcctl.sh

Create Mini-VPC
sudo ./vpcctl.sh create
```

Output:
```bash
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
```
## Test Connectivity

### Internal subnet communication:
```bash
sudo ip netns exec ns-public ping -c 2 10.10.2.2
sudo ip netns exec ns-private ping -c 2 10.10.1.2
```

### Internet access:
```bash
sudo ip netns exec ns-public ping -c 2 8.8.8.8
sudo ip netns exec ns-public curl -I http://example.com
sudo ip netns exec ns-private ping -c 2 8.8.8.8   # Should fail
```

Check interfaces:

```
ip link show br0
ip link show veth-br-public
ip link show veth-br-private
```
### Firewall Rules

ns-public allows outbound HTTP/HTTPS (ports 80, 443).

ns-private is internal-only; outbound blocked.

Rules are defined in the script and applied automatically with iptables.

### Clean Up
```bash
sudo ./vpcctl.sh delete
```

Output:
```bash
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
```