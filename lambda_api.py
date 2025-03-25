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
    temp_dir = None
    try:
        # 创建临时目录
        temp_dir = f"/tmp/mineru_temp_{int(time.time())}"
        os.makedirs(temp_dir, exist_ok=True)
        
        # 解码URL编码的键名
        decoded_key = urllib.parse.unquote_plus(input_key)
        logger.info(f"解码后的键名: {decoded_key}")
        
        # S3客户端
        s3_client = boto3.client('s3', region_name='cn-north-1')
        
        # 为文件创建安全的本地文件名（替换空格为下划线）
        original_filename = os.path.basename(decoded_key)
        safe_filename = original_filename.replace(' ', '_')
        local_file_path = os.path.join(temp_dir, safe_filename)
        
        # 检查文件是否存在
        try:
            # 首先尝试使用原始键名
            response = s3_client.head_object(Bucket=input_bucket, Key=decoded_key)
            file_size = response['ContentLength']
            if file_size > 100 * 1024 * 1024:  # 100MB限制
                logger.error(f"文件大小超过限制: {file_size} bytes")
                return False
            
            logger.info(f"下载文件: s3://{input_bucket}/{decoded_key} -> {local_file_path}")
            s3_client.download_file(input_bucket, decoded_key, local_file_path)
        except Exception as e:
            logger.error(f"使用原始键名下载失败: {str(e)}")
            # 尝试使用URL编码的键名
            encoded_key = urllib.parse.quote(decoded_key, safe='/')
            logger.info(f"尝试使用URL编码的键名: {encoded_key}")
            try:
                response = s3_client.head_object(Bucket=input_bucket, Key=encoded_key)
                file_size = response['ContentLength']
                if file_size > 100 * 1024 * 1024:  # 100MB限制
                    logger.error(f"文件大小超过限制: {file_size} bytes")
                    return False
                
                logger.info(f"使用URL编码的键名下载文件: s3://{input_bucket}/{encoded_key} -> {local_file_path}")
                s3_client.download_file(input_bucket, encoded_key, local_file_path)
            except Exception as e:
                logger.error(f"使用URL编码的键名下载也失败: {str(e)}")
                return False
        
        # 定义输出目录
        output_dir = os.path.join(temp_dir, "output")
        os.makedirs(output_dir, exist_ok=True)
        
        # 使用正确的conda路径
        conda_base = '/home/ec2-user/miniconda'
        conda_activate_cmd = f"source {conda_base}/etc/profile.d/conda.sh && conda activate mineru"
        magic_pdf_cmd = ["magic-pdf", "-p", local_file_path, "-o", output_dir, "-m", "auto"]
        
        # 使用shell=True执行conda激活，然后执行magic-pdf命令
        full_cmd = f"{conda_activate_cmd} && {' '.join(magic_pdf_cmd)}"
        logger.info(f"执行命令: {full_cmd}")
        
        # 添加环境变量
        env = os.environ.copy()
        env['PATH'] = f"{conda_base}/bin:{env['PATH']}"
        
        process = subprocess.Popen(
            full_cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env
        )
        
        stdout, stderr = process.communicate()
        
        if process.returncode != 0:
            logger.error(f"命令执行失败，返回码: {process.returncode}")
            logger.error(f"错误输出: {stderr}")
            logger.error(f"标准输出: {stdout}")
            return False
        
        logger.info(f"命令执行成功")
        
        # 准备S3输出路径
        name_without_suffix = os.path.splitext(original_filename)[0]
        base_output_prefix = f"output/{name_without_suffix}/"
        images_output_prefix = f"{base_output_prefix}images/"
        
        # 递归上传输出目录下所有文件到S3
        for root, dirs, files in os.walk(output_dir):
            for file in files:
                local_path = os.path.join(root, file)
                # 计算相对路径
                relative_path = os.path.relpath(local_path, output_dir)
                
                # 判断是否为图片文件
                is_image = file.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp'))
                
                if is_image:
                    # 图片文件上传到images目录
                    s3_key = f"{images_output_prefix}{file}"
                else:
                    # 非图片文件上传到主目录
                    s3_key = f"{base_output_prefix}{file}"
                
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
                    Key=images_output_prefix
                )
        except Exception as e:
            logger.error(f"确保images目录存在时出错: {str(e)}")
            # 不阻止处理流程继续
        
        logger.info(f"处理完成")
        return True
        
    except Exception as e:
        logger.error(f"处理出错: {str(e)}")
        logger.error(traceback.format_exc())
        return False
    finally:
        # 确保清理临时目录
        if temp_dir and os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                logger.info(f"已清理临时目录: {temp_dir}")
            except Exception as e:
                logger.error(f"清理临时目录时出错: {str(e)}")

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