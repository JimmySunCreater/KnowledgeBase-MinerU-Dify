#!/bin/bash

# 设置日志文件
LOG_FILE="/home/ec2-user/logs/mineru_api.log"
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 检查必要的目录和文件
CONDA_PATH="/home/ec2-user/miniconda"
SERVICE_DIR="/opt/mineru_service"
API_SCRIPT="$SERVICE_DIR/lambda_api.py"

# 检查 conda 安装
if [ ! -f "$CONDA_PATH/etc/profile.d/conda.sh" ]; then
    log "错误: 找不到 conda.sh 在 $CONDA_PATH/etc/profile.d/conda.sh"
    exit 1
fi

# 检查服务目录
if [ ! -d "$SERVICE_DIR" ]; then
    log "错误: 找不到服务目录 $SERVICE_DIR"
    exit 1
fi

# 检查 API 脚本
if [ ! -f "$API_SCRIPT" ]; then
    log "错误: 找不到 API 脚本 $API_SCRIPT"
    exit 1
fi

# 初始化 conda
log "初始化 conda..."
source "$CONDA_PATH/etc/profile.d/conda.sh"

# 激活环境
log "激活 mineru 环境..."
conda activate mineru

# 检查环境是否成功激活
if [ "$CONDA_DEFAULT_ENV" != "mineru" ]; then
    log "错误: 无法激活 mineru 环境"
    exit 1
fi

# 切换到服务目录
log "切换到服务目录 $SERVICE_DIR..."
cd "$SERVICE_DIR"

# 启动 API 服务
log "启动 API 服务..."
python3 "$API_SCRIPT"