#!/bin/bash

export HOME=/root
export GOCACHE=/tmp/gocache

# 将 needrestart 的模式设为自动重启，避免弹窗
export NEEDRESTART_MODE=a
# 如无需求可直接暂停 needrestart
# export NEEDRESTART_SUSPEND=1

# 将 APT/Debian 配置为非交互
export DEBIAN_FRONTEND=noninteractive


set -e

echo "🔧 开始安装 Shadowsocks（适配 ARM64）"

# === 更新系统 ===
sudo -E apt update && sudo -E apt upgrade -y
sudo apt install -y curl git

# === 检测系统架构 ===
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    GO_ARCH="arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    GO_ARCH="amd64"
else
    echo "❌ 不支持的架构: $ARCH"
    exit 1
fi

# === 安装 Go（自定义版本） ===
GO_VERSION="1.20.3"
cd /tmp
curl -LO "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
source ~/.profile

# 为[go install github.com/shadowsocks/go-shadowsocks2@latest]增加循环重试机制，应对网络抖动
echo "=== 安装 go-shadowsocks2 ==="
MAX_ATTEMPTS=5
ATTEMPT=1
echo "🔧 开始安装 go-shadowsocks2，最多尝试 $MAX_ATTEMPTS 次..."
until go install github.com/shadowsocks/go-shadowsocks2@latest; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
        echo "❌ go install 命令在尝试 $MAX_ATTEMPTS 次后仍然失败。"
        exit 1
    fi
    echo "⚠️ go install 失败，将在 10 秒后重试 (第 $ATTEMPT 次)..."
    sleep 10
done
echo "✅ go-shadowsocks2 安装成功。"
# go install github.com/shadowsocks/go-shadowsocks2@latest

# === 写入配置文件 ===
mkdir -p ~/.config
cat > ~/.config/shadowsocks.json <<EOF
{
  "server": "0.0.0.0",
  "port": 16888,
  "method": "aes-256-gcm",
  "password": "amazongreatvpn",
  "timeout": 300
}
EOF

# === 创建 systemd 服务 ===
sudo bash -c "cat > /etc/systemd/system/shadowsocks.service" <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/root/go/bin/go-shadowsocks2 -s "0.0.0.0:16888" -cipher "aes-256-gcm" -password "amazongreatvpn" -verbose -u
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === 启动服务 ===
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable shadowsocks
sudo systemctl start shadowsocks

# === 启用 BBR ===
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ Shadowsocks 安装完成，已启用 BBR，加密算法：aes-256-gcm，监听端口：16888"


### —— 在此处插入：禁用 IPv6 —— ###
echo "🔧 禁用 IPv6"
sudo tee -a /etc/sysctl.d/99-sysctl.conf <<'EOF'

# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
# 重新加载所有 sysctl 配置
sudo sysctl --system > /dev/null

# 验证（可选）
if sysctl net.ipv6.conf.all.disable_ipv6 | grep -q '= 1' \
  && sysctl net.ipv6.conf.default.disable_ipv6 | grep -q '= 1' \
  && sysctl net.ipv6.conf.lo.disable_ipv6 | grep -q '= 1'; then
  echo "✅ IPv6 已禁用"
else
  echo "⚠️ IPv6 禁用失败"
fi
### —— 禁用 IPv6 完成 —— ###

# === 新增：将外部 8838 端口流量转发到本地 16888 ===
echo "🔧 添加端口转发：8838 → 16888"
sudo iptables -t nat -A PREROUTING -p tcp --dport 8838 -j REDIRECT --to-ports 16888
sudo iptables -t nat -A PREROUTING -p udp --dport 8838 -j REDIRECT --to-ports 16888
echo "✅ 端口转发规则已生效"


# # 回传aws-instance-public-ip到Bussiness-server
# curl -s -X POST https://app.vpnin.xyz/api/aws/rent-userdata-callback
