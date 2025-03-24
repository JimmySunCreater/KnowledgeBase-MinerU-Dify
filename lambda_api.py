from flask import Flask, request, jsonify
import os
import boto3
import threading
import subprocess
import logging
import urllib.parse
import traceback
import shutil
import time

# 配置日志
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    filename='/var/log/mineru_api.log',
    filemode='a'
)
logger = logging.getLogger(__name__)

# 添加控制台处理器
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)

app = Flask(__name__)

def process_file_in_mineru_env(input_bucket, input_key, file_type):
    """使用命令行方式处理文件"""
    try:
        # 创建临时目录
        temp_dir = f"/tmp/mineru_temp_{int(time.time())}"
        os.makedirs(temp_dir, exist_ok=True)
        
        # 解码URL编码的键名
        decoded_key = urllib.parse.unquote_plus(input_key)
        logger.info(f"解码后的键名: {decoded_key}")
        
        # S3客户端
        s3_client = boto3.client('s3')
        
        # 为文件创建安全的本地文件名（替换空格为下划线）
        original_filename = os.path.basename(decoded_key)
        safe_filename = original_filename.replace(' ', '_')
        local_file_path = os.path.join(temp_dir, safe_filename)
        
        logger.info(f"下载文件: s3://{input_bucket}/{decoded_key} -> {local_file_path}")
        s3_client.download_file(input_bucket, decoded_key, local_file_path)
        
        # 定义输出目录
        output_dir = os.path.join(temp_dir, "output")
        os.makedirs(output_dir, exist_ok=True)
        
        # 执行magic-pdf命令，使用正确的参数名 --output-dir 而不是 --output
        cmd = f"source ~/miniconda3/etc/profile.d/conda.sh && conda activate mineru && magic-pdf -p '{local_file_path}' -o '{output_dir}' -m auto"
        logger.info(f"执行命令: {cmd}")
        
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            logger.error(f"命令执行失败: {result.stderr}")
            logger.error(f"命令输出: {result.stdout}")
            return False
        
        logger.info(f"命令执行成功")
        
        # 准备S3输出路径 (使用原始文件名，不带扩展名)
        name_without_suffix = os.path.splitext(original_filename)[0]
        output_prefix = f"Output/{name_without_suffix}/"
        
        # 递归上传输出目录下所有文件到S3
        for root, dirs, files in os.walk(output_dir):
            for file in files:
                local_path = os.path.join(root, file)
                # 计算相对路径，以便在S3中保持相同的目录结构
                relative_path = os.path.relpath(local_path, output_dir)
                s3_key = f"{output_prefix}{relative_path}"
                
                logger.info(f"上传: {local_path} -> s3://{input_bucket}/{s3_key}")
                s3_client.upload_file(local_path, input_bucket, s3_key)
        
        # 确保images目录存在
        try:
            has_images = False
            for root, dirs, files in os.walk(output_dir):
                if "images" in dirs:
                    has_images = True
                    break
                    
            if not has_images:
                logger.info("未找到images文件夹，创建空的images目录")
                s3_client.put_object(
                    Bucket=input_bucket,
                    Key=f"{output_prefix}images/"
                )
        except Exception as e:
            logger.error(f"确保images目录存在时出错: {str(e)}")
            # 不阻止处理流程继续
        
        # 清理临时文件
        shutil.rmtree(temp_dir)
        logger.info(f"处理完成，已清理临时文件")
        return True
        
    except Exception as e:
        logger.error(f"处理出错: {str(e)}")
        logger.error(traceback.format_exc())
        return False

@app.route('/convert', methods=['POST'])
def convert_file():
    try:
        data = request.json
        if not data:
            return jsonify({"status": "错误", "message": "缺少JSON请求体"}), 400
        
        input_bucket = data.get('bucket')
        input_key = data.get('key')
        file_type = data.get('file_type', 'pdf')  # 默认为pdf
        
        if not input_bucket or not input_key:
            return jsonify({"status": "错误", "message": "缺少必要参数: bucket 或 key"}), 400
        
        logger.info(f"收到转换请求: {input_key} (类型: {file_type})")
        
        # 在后台线程中启动处理
        thread = threading.Thread(target=process_file_in_mineru_env, args=(input_bucket, input_key, file_type))
        thread.start()
        
        return jsonify({
            "status": "处理已开始", 
            "message": f"正在处理 {input_key} (类型: {file_type})"
        })
    except Exception as e:
        logger.error(f"转换请求处理失败: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"status": "错误", "message": f"服务器错误: {str(e)}"}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "健康", "message": "API服务正在运行"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
