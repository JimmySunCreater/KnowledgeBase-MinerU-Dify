#!/bin/bash

# 找出conda的实际位置
if [ -f ~/miniconda3/etc/profile.d/conda.sh ]; then
    source ~/miniconda3/etc/profile.d/conda.sh
elif [ -f ~/anaconda3/etc/profile.d/conda.sh ]; then
    source ~/anaconda3/etc/profile.d/conda.sh
else
    # 尝试查找conda.sh的位置
    CONDA_PATH=$(find / -name conda.sh -path "*/etc/profile.d/conda.sh" 2>/dev/null | head -1)
    if [ -n "$CONDA_PATH" ]; then
        source "$CONDA_PATH"
    else
        echo "无法找到conda.sh，请手动设置conda路径"
        exit 1
    fi
fi

# 激活conda环境
conda activate mineru

# 运行API服务
cd /opt/mineru_service
sudo python lambda_api.py
