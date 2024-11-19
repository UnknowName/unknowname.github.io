#!/bin/bash
source /etc/profile
export PATH
set -e


function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

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


function set_sysctl() {
    cat > 999-init.conf << EOF
    # 出现SYN等待队列溢出时启用cookie处理，防范少量的SYN攻击。
    net.ipv4.tcp_syncookies = 1
    # 本地发起连接的端口范围
    net.ipv4.ip_local_port_range = 1025 65000
    # Elasticsearch 最低要求
    vm.max_map_count = 362144
    # 内核禁用SWAP
    vm.swappiness = 1
    # 端口的监听队列长度，当一个请求(request)尚未被处理或者建立时
    net.core.somaxconn = 4096
    # 每个端口连接最大数，包括连接，已连接，新建立的连接
    net.ipv4.tcp_max_syn_backlog = 4096
    # 来自阿里云
    net.ipv4.conf.all.rp_filter= 0
    net.ipv4.conf.default.rp_filter= 0
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
    if [ -f /etc/sysctl.d/999-init.conf ]; then
        log "file exist. add to /etc/sysctl.d/1000-init.conf"
        mv 999-init.conf /etc/sysctl.d/1000-init.conf
        sysctl -p /etc/sysctl.d/1000-init.conf
    else
        log "add to /etc/sysctl.d/999-init.conf"
        mv 999-init.conf /etc/sysctl.d/
        sysctl -p /etc/sysctl.d/999-init.conf
    fi
}

function set_limit() {
    which bc > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "Can't find bc, install bc"
        yum install -y bc || apt install bc -y
    fi
    filemax=$(cat /proc/sys/fs/file-max)
    limit_max=$(echo "scale=0; ${filemax} * 8 / 10" | bc)
    log "set soft and hard nofile limits ${limit_max}"
    echo "* soft nofile ${limit_max}" >> /etc/security/limits.conf
    echo "* hard nofile ${limit_max}" >> /etc/security/limits.conf
}


function set_docker() {
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
    name=$(get_release)
    if [ ${name} = "ubuntu" ]; then
        sed -i '/native.cgroupdriver=systemd/d' daemon.json
    fi
    log "set docker daemon.json"
    if [ -f /etc/docker/daemon.json ]; then
        log "mv /etc/docker/daemon.json to /etc/docker/daemon.json.bak"
        mv /etc/docker/daemon.json /etc/docker/daemon.json.bak
    fi
    mv daemon.json /etc/docker 
    systemctl restart docker
}


function set_all() {
    log "set kernel sysctl.conf"
    set_sysctl
    log "set limits.conf"
    set_limit
    log "set docker"
    set_docker
}


arg=$1
cd /tmp
if [ "$arg" = "--help" ]; then
    echo "limit  set system limits.conf"
    echo "docker set docker's daemon.json"
    echo "sysctl set sysctl.conf"
    echo "init   set limit, docker's daemon.conf ,sysctl.conf, Only used for first time"
    exit 0
elif [ "$arg" = "limit" ]; then
    echo "set limits.conf"
    set_limit
elif [ "$arg" = "docker" ]; then
    echo "set docker's daemon.json"
    set_docker
elif [ "$arg" = "sysctl" ]; then
    echo "set sysctl.conf"
    set_sysctl
elif [ "$arg" = "init" ]; then
    echo "set limits.conf, install and set docker,set sysctl.conf"
    set_all
else
    echo "use --help to see help"
fi