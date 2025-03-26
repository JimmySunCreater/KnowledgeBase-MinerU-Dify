import json

def main(llm_output) -> dict:
    try:
        # 检查输入类型并处理
        if isinstance(llm_output, dict) and "text" in llm_output:
            json_str = llm_output["text"]
        elif isinstance(llm_output, str):
            json_str = llm_output
        else:
            return {"Content": "无效的输入格式", "URL": ""}
        
        # 解析JSON字符串
        parsed_data = json.loads(json_str)
        
        # 提取Content和URL
        content = parsed_data.get("Content", "")
        url = parsed_data.get("URL", "")
        
        # 保持原始格式返回
        return {
            "Content": content,
            "URL": url
        }
    except Exception as e:
        return {
            "Content": f"处理异常: {str(e)}",
            "URL": ""
        }