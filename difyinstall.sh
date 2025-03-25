#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 总步骤数
TOTAL_STEPS=8
CURRENT_STEP=0

# 打印彩色信息函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP+1))
    echo -e "\n${BLUE}[步骤 $CURRENT_STEP/$TOTAL_STEPS]${NC} ${GREEN}$1${NC}"
}

# 检测操作系统类型
detect_os() {
    print_step "检测操作系统类型"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        print_info "检测到操作系统: $OS $VERSION"
    else
        print_error "无法检测操作系统类型，退出安装"
        exit 1
    fi
}

# 安装基础环境 - Amazon Linux
install_base_amazon() {
    print_step "更新系统并安装基础工具"
    print_info "使用 Amazon Linux 安装方式"
    sudo yum update -y
    sudo yum install -y yum-utils git curl wget
}

# 安装基础环境 - Ubuntu
install_base_ubuntu() {
    print_step "更新系统并安装基础工具"
    print_info "使用 Ubuntu 安装方式"
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common git wget
}

# 添加GitHub520 hosts以改善GitHub访问
improve_github_access() {
    print_step "添加GitHub520 hosts以改善GitHub访问"
    print_info "下载GitHub520 hosts文件..."
    sudo curl https://raw.hellogithub.com/hosts | sudo tee -a /etc/hosts
    if [ $? -eq 0 ]; then
        print_info "GitHub hosts添加成功"
    else
        print_warning "GitHub hosts添加失败，可能会影响后续Git操作，但将继续安装"
    fi
}

# 安装Docker - Amazon Linux
install_docker_amazon() {
    print_step "安装Docker"
    print_info "使用 Amazon Linux 安装方式"
    sudo yum install -y docker
    
    # 启动并设置Docker开机自启
    print_info "启动Docker并设置开机自启..."
    sudo systemctl start docker
    sudo systemctl enable docker
}

# 安装Docker - Ubuntu
install_docker_ubuntu() {
    print_step "安装Docker"
    print_info "使用 Ubuntu 安装方式"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    
    # 启动并设置Docker开机自启
    print_info "启动Docker并设置开机自启..."
    sudo systemctl start docker
    sudo systemctl enable docker
}

# 安装Docker Compose
install_docker_compose() {
    print_step "安装Docker Compose"
    sudo curl -L "https://d3d2iaoi1ibop8.cloudfront.net/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    # 验证安装
    docker_compose_version=$(sudo docker-compose version)
    print_info "Docker Compose安装完成: $docker_compose_version"
}

# 配置Docker镜像加速
configure_docker_mirrors() {
    print_step "配置Docker镜像加速"
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://2a6bf1988cb6428c877f723ec7530dbc.mirror.swr.myhuaweicloud.com",
    "https://docker.m.daocloud.io",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://dockerhub.icu",
    "https://docker.registry.cyou",
    "https://docker-cf.registry.cyou",
    "https://dockercf.jsdelivr.fyi",
    "https://docker.jsdelivr.fyi",
    "https://dockertest.jsdelivr.fyi",
    "https://mirror.aliyuncs.com",
    "https://dockerproxy.com",
    "https://docker.nju.edu.cn",
    "https://docker.mirrors.sjtug.sjtu.edu.cn",
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.iscas.ac.cn",
    "https://docker.rainbond.cc"
  ]
}
EOF

    # 重启Docker服务
    print_info "重启Docker服务以应用镜像加速配置..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
}

# 检查Docker状态
check_docker_status() {
    print_step "检查Docker服务状态"
    docker_status=$(sudo systemctl is-active docker)
    if [ "$docker_status" = "active" ]; then
        print_info "Docker服务运行正常"
    else
        print_error "Docker服务运行异常，请检查"
        exit 1
    fi
}

# 安装Dify
install_dify() {
    print_step "安装Dify"
    
    # 清理可能存在的旧文件
    rm -rf dify dify-main.zip dify-main

    # 尝试克隆Dify项目
    print_info "尝试从GitHub克隆Dify项目(超时时间30秒，最低速度100KB/s)..."
    
    # 使用进度监控克隆
    if timeout 30 git clone --progress https://github.com/langgenius/dify.git 2>&1 | tee /tmp/git_progress | \
       awk '
         BEGIN { slow_count = 0 }
         /Receiving objects:/ {
           if ($3 ~ /%/) {
             speed = $(NF-1)
             unit = $NF
             if (unit == "KiB/s" && speed < 100) {
               slow_count++
               if (slow_count >= 3) {
                 print "Speed too slow" > "/dev/stderr"
                 exit 1
               }
             } else {
               slow_count = 0
             }
           }
         }
       ' && wait $! && [ -d "dify" ] && [ -d "dify/docker" ]; then
        print_info "GitHub克隆成功"
    else
        print_warning "GitHub克隆失败或目录结构不完整，尝试从备用源下载..."
        
        # 清理可能存在的不完整文件
        rm -rf dify
        
        # 下载zip文件
        print_info "从备用源下载Dify..."
        if wget https://d3d2iaoi1ibop8.cloudfront.net/dify-main.zip && [ -f "dify-main.zip" ]; then
            print_info "下载成功，正在解压..."
            if unzip dify-main.zip && [ -d "dify-main" ]; then
                mv dify-main dify
                rm dify-main.zip
                print_info "解压完成"
            else
                print_error "解压失败，安装无法继续"
                rm -f dify-main.zip
                exit 1
            fi
        else
            print_error "备用源下载失败，安装无法继续"
            rm -f dify-main.zip
            exit 1
        fi
    fi

    # 验证必要的目录结构
    if [ ! -d "dify" ] || [ ! -d "dify/docker" ]; then
        print_error "Dify目录结构不完整，安装失败"
        exit 1
    fi

    cd dify/docker || {
        print_error "无法进入Dify项目目录，请检查安装是否成功"
        exit 1
    }

    # 复制环境配置文件
    print_info "配置Dify环境..."
    if [ -f ".env.example" ]; then
        cp .env.example .env
    else
        print_error "环境配置模板文件不存在"
        exit 1
    fi
    
    # 启动服务
    print_info "启动Dify服务..."
    sudo docker-compose up -d
    
    # 检查服务状态
    print_info "检查服务状态..."
    sudo docker-compose ps
}

# 安装完成信息
show_completion_info() {
    print_step "安装完成"
    
    # 获取服务器IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
    
    print_info "Dify 安装成功！"
    print_info "您现在可以通过 http://$SERVER_IP 访问Dify了"
    print_info "首次访问时，您需要设置管理员账户和密码"
    
    # 打印容器运行状态
    echo -e "\n${GREEN}容器运行状态:${NC}"
    if [ -d "dify/docker" ]; then
        sudo docker ps
    else
        print_warning "无法显示容器状态，请手动检查"
    fi
}

# 主函数
main() {
    echo -e "${BLUE}===== Dify 自动安装脚本 =====${NC}"
    echo -e "${GREEN}本脚本将自动识别系统类型并安装Dify${NC}\n"
    
    # 检测操作系统
    detect_os
    
    # 根据操作系统类型安装基础环境
    case $OS in
        amzn|amazonlinux)
            install_base_amazon
            ;;
        ubuntu)
            install_base_ubuntu
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    # 改善GitHub访问
    improve_github_access
    
    # 根据操作系统类型安装Docker
    case $OS in
        amzn|amazonlinux)
            install_docker_amazon
            ;;
        ubuntu)
            install_docker_ubuntu
            ;;
    esac
    
    # 安装Docker Compose
    install_docker_compose
    
    # 配置Docker镜像加速
    configure_docker_mirrors
    
    # 检查Docker状态
    check_docker_status
    
    # 安装Dify
    install_dify
    
    # 显示安装完成信息
    show_completion_info
}

# 执行主函数
main