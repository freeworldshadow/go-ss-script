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
echo "📦 开始更新系统包..."
sudo -E apt update && sudo -E apt upgrade -y
echo "✅ 系统包更新完成"

echo "📦 开始安装基础依赖包（curl, git）..."
sudo apt install -y curl git
echo "✅ 基础依赖包安装完成"

# === 检测系统架构 ===
echo "🔍 开始检测系统架构..."
ARCH=$(uname -m)
echo "📋 检测到系统架构: $ARCH"
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    GO_ARCH="arm64"
    echo "✅ 系统架构匹配: ARM64"
elif [[ "$ARCH" == "x86_64" ]]; then
    GO_ARCH="amd64"
    echo "✅ 系统架构匹配: AMD64"
else
    echo "❌ 不支持的架构: $ARCH"
    exit 1
fi

# === 安装 Go（自定义版本） ===
echo "🚀 开始安装 Golang..."
GO_VERSION="1.20.3"
echo "📋 Golang 版本: $GO_VERSION"
echo "📋 目标架构: $GO_ARCH"

echo "📂 切换到临时目录 /tmp"
cd /tmp

# 为 Golang 下载添加重试机制
echo "📥 开始下载 Golang 安装包，最多尝试 5 次..."
MAX_ATTEMPTS=5
ATTEMPT=1
until curl -LO "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
        echo "❌ Golang 下载在尝试 $MAX_ATTEMPTS 次后仍然失败。"
        exit 1
    fi
    echo "⚠️ Golang 下载失败，将在 10 秒后重试 (第 $ATTEMPT 次)..."
    sleep 10
done
echo "✅ Golang 安装包下载成功"

echo "📦 开始解压 Golang 到 /usr/local..."
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
echo "✅ Golang 解压完成"

echo "⚙️ 配置 Golang 环境变量..."
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
source ~/.profile
echo "✅ Golang 环境变量配置完成"

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
echo "📝 开始创建 Shadowsocks 配置文件..."
mkdir -p ~/.config
echo "📂 创建配置目录: ~/.config"
cat > ~/.config/shadowsocks.json <<EOF
{
  "server": "0.0.0.0",
  "port": 16888,
  "method": "aes-256-gcm",
  "password": "amazongreatvpn",
  "timeout": 300
}
EOF
echo "✅ Shadowsocks 配置文件创建完成"

# === 创建 systemd 服务 ===
echo "⚙️ 开始创建 systemd 服务文件..."
sudo bash -c "cat > /etc/systemd/system/shadowsocks.service" <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/root/go/bin/go-shadowsocks2 -s "0.0.0.0:16888" -cipher "aes-256-gcm" -password "amazongreatvpn" -verbose
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
echo "✅ systemd 服务文件创建完成"

# === 启动服务 ===
echo "🚀 开始启动 Shadowsocks 服务..."
echo "🔄 重新加载 systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
echo "✅ systemd daemon 重新加载完成"

echo "⚙️ 启用 Shadowsocks 服务开机自启..."
sudo systemctl enable shadowsocks
echo "✅ Shadowsocks 服务开机自启已启用"

echo "▶️ 启动 Shadowsocks 服务..."
sudo systemctl start shadowsocks
echo "✅ Shadowsocks 服务启动完成"

# === 启用 BBR ===
echo "🚀 开始启用 BBR 网络优化..."
echo "⚙️ 配置 BBR 相关内核参数..."
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
echo "🔄 应用内核参数配置..."
sudo sysctl -p
echo "✅ BBR 网络优化启用完成"

echo "✅ Shadowsocks 安装完成，已启用 BBR，加密算法：aes-256-gcm，监听端口：16888"


### —— 在此处插入：禁用 IPv6 —— ###
echo "🔧 开始禁用 IPv6..."
echo "📝 写入 IPv6 禁用配置到 sysctl..."
sudo tee -a /etc/sysctl.d/99-sysctl.conf <<'EOF'

# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
echo "✅ IPv6 禁用配置写入完成"

echo "🔄 重新加载所有 sysctl 配置..."
# 重新加载所有 sysctl 配置
sudo sysctl --system > /dev/null
echo "✅ sysctl 配置重新加载完成"

echo "🔍 验证 IPv6 禁用状态..."
# 验证（可选）
if sysctl net.ipv6.conf.all.disable_ipv6 | grep -q '= 1' \
  && sysctl net.ipv6.conf.default.disable_ipv6 | grep -q '= 1' \
  && sysctl net.ipv6.conf.lo.disable_ipv6 | grep -q '= 1'; then
  echo "✅ IPv6 已成功禁用"
else
  echo "⚠️ IPv6 禁用失败"
fi
### —— 禁用 IPv6 完成 —— ###

# === 新增：将外部 8838 端口流量转发到本地 16888 ===
echo "🔧 开始配置端口转发：8838 → 16888"
echo "⚙️ 添加 TCP 端口转发规则..."
sudo iptables -t nat -A PREROUTING -p tcp --dport 8838 -j REDIRECT --to-ports 16888
echo "⚙️ 添加 UDP 端口转发规则..."
sudo iptables -t nat -A PREROUTING -p udp --dport 8838 -j REDIRECT --to-ports 16888
echo "✅ 端口转发规则配置完成"


# 回传aws-instance-public-ip到Bussiness-server
echo "📡 开始回传实例信息到业务服务器..."
curl -s -X POST https://app.vpnin.xyz/api/aws/rent-userdata-callback
echo "✅ 实例信息回传完成"
