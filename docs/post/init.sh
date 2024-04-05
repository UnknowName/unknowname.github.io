#!/bin/bash
source /etc/profile
export PATH


function get_release() {
   if [ -f /etc/redhat-release ];then
     echo "centos"
     exit 0
   fi
   grep "Ubuntu" /etc/issue > /dev/null
   if [ $? -eq 0 ];then
       echo "ubuntu"
       exit 0
   fi
   echo "Unsupport Linux release"
   exit 1
}


function init_sysctl() {
    cat > 999-init.conf << EOF
    # 出现SYN等待队列溢出时启用cookie处理，防范少量的SYN攻击。
    net.ipv4.tcp_syncookies = 1
    # 本地发起连接的端口范围
    net.ipv4.ip_local_port_range = 1025 65000
    # Elasticsearch 最低要求
    vm.max_map_count = 262144
    # 内核禁用SWAP
    vm.swappiness = 1
    # 端口的监听队列长度，当一个请求(request)尚未被处理或者建立时
    net.core.somaxconn = 4096
    # 每个端口连接最大数，包括连接，已连接，新建立的连接
    net.ipv4.tcp_max_syn_backlog = 4096
    # 来自阿里云
    net.ipv4.conf.all.rp_filter=0
    net.ipv4.conf.default.rp_filter=0
    net.ipv4.conf.default.arp_announce = 2
    net.ipv4.conf.lo.arp_announce=2
    net.ipv4.conf.all.arp_announce=2
    net.ipv4.tcp_max_tw_buckets = 5000
    net.ipv4.tcp_syncookies = 1
    net.ipv4.tcp_max_syn_backlog = 1024
    net.ipv4.tcp_synack_retries = 2
    kernel.sysrq=1
    # 能够更快地回收TIME-WAIT套接字
    net.ipv4.tcp_tw_recycle = 1
    # 减少FIN_WAIT2
    net.netfilter.nf_conntrack_tcp_timeout_established=12400
    net.ipv4.tcp_syncookies = 1
    net.ipv4.tcp_fin_timeout = 30
    net.ipv4.tcp_max_tw_buckets = 262144
EOF
}

function set_limit() {
    filemax=$(cat /proc/sys/fs/file-max)
    limit_max=$(echo "scale=0; ${filemax} * 8 / 10" | bc)
    grep "nofile" /etc/security/limits.conf | grep -v "#"
    if [ $? -ne 0 ]; then
        log "set soft nofile limits ${limit_max}"
        echo "* soft nofile ${limit_max}" >> /etc/security/limits.conf
    else
        log "exist soft limits, skip"
    fi
}

function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

function main() {
    cd /tmp
    cat > daemon.json << EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "registry-mirrors": ["https://registry.docker-cn.com", "https://docker.mirrors.ustc.edu.cn"], 
    "max-concurrent-downloads": 10,
    "live-restore": true,
    "log-opts": {
        "max-file": "3",
        "max-size": "10M"
    },
    "insecure-registries" : ["hub.siss.io:5000", "docker.sixun.hw:5000"]
}
EOF
    log "Get system disturibute version"
    name=$(get_release)
    log "set docker"
    if [ ${name} = "ubuntu" ]; then
        sed -i '/native.cgroupdriver=systemd/d' daemon.json
    fi
    if ! [ -f /etc/docker/daemon.json ]; then
        mv daemon.json /etc/docker
    fi
    log "set kernel sysctl.conf"
    init_sysctl
    if ! [ -f /etc/sysctl.d/999-init.conf ]; then
        mv 999-init.conf /etc/sysctl.d/
        sysctl -p /etc/sysctl.d/999-init.conf
    fi
    log "set limit"
    set_limit
}


main