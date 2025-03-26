#!/bin/bash

echo "开始安装 MinerU API 服务..."

# 更新 hosts 文件
echo "0. 更新 hosts 文件以访问 GitHub..."
wget --timeout=30 --tries=3 --waitretry=5 -O - https://raw.hellogithub.com/hosts | sudo tee -a /etc/hosts
echo "   hosts 文件更新完成"

# 安装 Miniconda
echo "1. 安装 Miniconda..."
wget --timeout=30 --tries=3 --waitretry=5 https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
# 使用 -u 参数确保更新已存在的安装
bash ~/miniconda.sh -b -u -p /home/ec2-user/miniconda

# 添加 conda 到当前会话的 PATH
export PATH="/home/ec2-user/miniconda/bin:$PATH"

# 初始化 conda 并添加到 .bashrc
echo "2. 初始化 Conda 并添加到启动项..."
/home/ec2-user/miniconda/bin/conda init bash

# 确保当前会话可以使用 conda 命令
source ~/.bashrc

# 检查 conda 安装
echo "3. 验证 conda 安装..."
conda --version
echo "   Conda 安装完成"

# 创建并激活 conda 环境
echo "4. 创建并激活 mineru 环境..."
conda create -n mineru python=3.10 -y
source /home/ec2-user/miniconda/bin/activate mineru
echo "   mineru 环境创建并激活完成"

# 安装 pip 和必要的 Python 包
echo "4.1. 安装 pip 和必要的 Python 包..."
sudo yum install python3-pip mesa-libGL -y
source /home/ec2-user/miniconda/bin/activate mineru
pip install boto3 flask
echo "   pip 和必要的 Python 包安装完成"

# 安装依赖包
echo "5. 安装依赖包..."
pip install -U "magic-pdf[full]" --extra-index-url https://wheels.myhloli.com -i https://mirrors.aliyuncs.com/pypi/simple
echo "   依赖包安装完成"

# 安装 modelscope 并下载预训练模型
echo "5.1. 安装 modelscope..."
pip install modelscope
echo "    modelscope 安装完成"

echo "5.2. 下载模型下载脚本..."
wget --timeout=30 --tries=3 --waitretry=5 https://gcore.jsdelivr.net/gh/opendatalab/MinerU@master/scripts/download_models.py -O download_models.py
echo "    下载脚本获取完成"

echo "5.3. 执行模型下载..."
python download_models.py
echo "    模型下载完成"

# 创建目标目录（如果不存在）
echo "6. 创建目标目录 /opt/mineru_service/..."
sudo mkdir -p /opt/mineru_service/
echo "   目录创建完成"

# 下载 lambda_api.py 到目标目录
echo "7. 下载 lambda_api.py..."
if ! sudo wget --timeout=30 --tries=3 --waitretry=5 -O /opt/mineru_service/lambda_api.py https://raw.githubusercontent.com/JimmySunCreater/KnowledgeBase-MinerU-Dify/main/lambda_api.py; then
    echo "   从 GitHub 下载失败，尝试从备用源下载..."
    sudo wget --timeout=30 --tries=3 --waitretry=5 -O /opt/mineru_service/lambda_api.py https://d3d2iaoi1ibop8.cloudfront.net/lambda_api.py
fi
echo "   lambda_api.py 下载完成"

# 下载 start_mineru_api.sh 到目标目录
echo "8. 下载 start_mineru_api.sh..."
if ! sudo wget --timeout=30 --tries=3 --waitretry=5 -O /opt/mineru_service/start_mineru_api.sh https://raw.githubusercontent.com/JimmySunCreater/KnowledgeBase-MinerU-Dify/main/start_mineru_api.sh; then
    echo "   从 GitHub 下载失败，尝试从备用源下载..."
    sudo wget --timeout=30 --tries=3 --waitretry=5 -O /opt/mineru_service/start_mineru_api.sh https://d3d2iaoi1ibop8.cloudfront.net/start_mineru_api.sh
fi
echo "   start_mineru_api.sh 下载完成"

# 添加执行权限
echo "9. 添加执行权限..."
sudo chmod +x /opt/mineru_service/start_mineru_api.sh
echo "   执行权限添加完成"

# 修改 start_mineru_api.sh 以包含正确的 conda 路径
echo "10. 更新启动脚本中的 conda 路径..."
sudo sed -i "s|conda activate|source $HOME/miniconda/bin/activate|g" /opt/mineru_service/start_mineru_api.sh
echo "    启动脚本更新完成"

# 下载服务配置文件
echo "11. 下载服务配置文件..."
if ! sudo wget --timeout=30 --tries=3 --waitretry=5 -O /etc/systemd/system/mineru-api.service https://raw.githubusercontent.com/JimmySunCreater/KnowledgeBase-MinerU-Dify/main/mineru-api.service; then
    echo "    从 GitHub 下载失败，尝试从备用源下载..."
    sudo wget --timeout=30 --tries=3 --waitretry=5 -O /etc/systemd/system/mineru-api.service https://d3d2iaoi1ibop8.cloudfront.net/mineru-api.service
fi
echo "    服务配置文件下载完成"

# 更新服务文件以使用完整路径
echo "12. 更新服务文件中的路径..."
sudo sed -i '/^ExecStart=/c\ExecStart=/bin/bash -c "source /home/ec2-user/miniconda/bin/activate mineru && python3 /opt/mineru_service/lambda_api.py"' /etc/systemd/system/mineru-api.service
echo "    服务文件更新完成"

# 重新加载 systemd 配置
echo "13. 重新加载 systemd 配置..."
sudo systemctl daemon-reload
echo "    systemd 配置加载完成"

# 启用服务（设置开机自启动）
echo "14. 启用 mineru-api 服务开机自启动..."
sudo systemctl enable mineru-api.service
echo "    服务自启动设置完成"

# 启动服务
echo "15. 启动 mineru-api 服务..."
sudo systemctl start mineru-api.service
echo "    服务已启动"

# 检查服务状态
echo "16. 检查服务状态..."
sudo systemctl status mineru-api.service --no-pager
echo "    状态检查完成"

echo "17. 安装完成！MinerU API 服务已成功配置并启动"
echo "重要提示：请注意，如果您在新会话中需要使用 conda 命令，请先执行 'source ~/.bashrc'"