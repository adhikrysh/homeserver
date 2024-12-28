#!/bin/bash
# Applies TCP BBR + latency tuning
# Docs: /home/drc/docs/tcp-bbr-tuning.md

sudo tee /etc/sysctl.d/99-network-latency.conf > /dev/null << 'EOF'
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
EOF

sudo sysctl --system

echo ""
echo "Verifying:"
sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_fastopen net.ipv4.tcp_slow_start_after_idle
