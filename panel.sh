#!/bin/bash

CONFIG="/usr/local/etc/xray/config.json"

# ========== 工具 ==========
random_port() {
    echo $((RANDOM%10000+20000))
}

select_port() {
    echo "1) 随机端口"
    echo "2) 自定义端口"
    read -p "请选择: " p
    if [ "$p" = "1" ]; then
        PORT=$(random_port)
        echo "随机端口: $PORT"
    else
        read -p "输入端口: " PORT
    fi
}

select_sni() {
    echo "SNI推荐："
    echo "1) www.cloudflare.com"
    echo "2) www.apple.com"
    echo "3) www.microsoft.com"
    echo "4) www.amazon.com"
    echo "5) www.google.com"
    echo "6) apps.apple.com"
    echo "7) 自定义"

    read -p "选择SNI: " s

    case $s in
        1) SNI="www.cloudflare.com" ;;
        2) SNI="www.apple.com" ;;
        3) SNI="www.microsoft.com" ;;
        4) SNI="www.amazon.com" ;;
        5) SNI="www.google.com" ;;
        6) SNI="apps.apple.com" ;;
        7) read -p "输入SNI: " SNI ;;
        *) SNI="www.cloudflare.com" ;;
    esac
}

gen_uuid() {
    cat /proc/sys/kernel/random/uuid
}

install_xray() {
    bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) install
}

# ========== Reality ==========
install_reality() {
    install_xray
    select_port
    select_sni

    UUID=$(gen_uuid)
    SHORTID=$(openssl rand -hex 8)

    KEYS=$(xray x25519)
    PRIVATE=$(echo "$KEYS" | grep Private | awk '{print $3}')
    PUBLIC=$(echo "$KEYS" | grep Public | awk '{print $3}')

    cat > $CONFIG <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$UUID",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "$SNI:443",
        "serverNames": ["$SNI"],
        "privateKey": "$PRIVATE",
        "shortIds": ["$SHORTID"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    systemctl restart xray
    systemctl enable xray

    IP=$(curl -s ifconfig.me)

    echo "===== Reality ====="
    echo "IP: $IP"
    echo "PORT: $PORT"
    echo "UUID: $UUID"
    echo "SNI: $SNI"
    echo "PUBLIC KEY: $PUBLIC"
    echo "LINK:"
    echo "vless://$UUID@$IP:$PORT?encryption=none&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC&sid=$SHORTID&type=tcp&flow=xtls-rprx-vision#Reality"
}

# ========== VMESS ==========
install_vmess() {
    install_xray
    select_port

    UUID=$(gen_uuid)

    cat > $CONFIG <<EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [{"id": "$UUID"}]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "/ws"}
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    systemctl restart xray
    IP=$(curl -s ifconfig.me)

    echo "VMESS ws://$IP:$PORT/ws"
    echo "UUID: $UUID"
}

# ========== Shadowsocks ==========
install_ss() {
    install_xray
    select_port

    PASS=$(openssl rand -base64 12)

    cat > $CONFIG <<EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "shadowsocks",
    "settings": {
      "method": "aes-256-gcm",
      "password": "$PASS"
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    systemctl restart xray
    IP=$(curl -s ifconfig.me)

    echo "SS: $IP:$PORT"
    echo "PASS: $PASS"
}

# ========== BBR ==========
enable_bbr() {
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo "BBR OK"
}

# ========== 主菜单 ==========
while true; do
clear
echo "=============================="
echo "  VLESS / VMESS / SS 面板"
echo "=============================="
echo "1) VLESS + Reality（直连）"
echo "2) VMESS + WS（软路由）"
echo "3) Shadowsocks"
echo "4) 启用 BBR"
echo "5) 修改端口（未做持久化）"
echo "6) 修改用户名/密码（未实现）"
echo "7) 卸载"
echo "8) 查看链接（基础）"
echo "9) 退出"
echo "=============================="

read -p "选择: " c

case $c in
1) install_reality ;;
2) install_vmess ;;
3) install_ss ;;
4) enable_bbr ;;
7) systemctl stop xray && rm -rf /usr/local/etc/xray ;;
8) cat $CONFIG ;;
9) exit ;;
*) echo "无效" ;;
esac

read -p "回车继续..."
done
