{ config, lib, pkgs, ... }:

let
  # 要拉取的模型列表
  models = [
    # 模型介绍地址https://www.modelscope.cn/models/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
    # "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
    # 模型介绍地址https://www.modelscope.cn/models/ZhipuAI/GLM-4.6V-Flash
    # "ZhipuAI/GLM-4.6V-Flash" # 10B
    # 模型介绍地址https://www.modelscope.cn/models/qwen/Qwen2.5-7B-Instruct-gguf
    "Qwen/Qwen2.5-7B-Instruct-GGUF" # 默认latest为Q4_K_M量化版本，还有Q4_0
    # "Qwen/Qwen2.5-7B-Instruct-GGUF:Q8_0" # 可以这样指定比Q4_K_M更大的Q8_0量化版本
    # "Qwen/Qwen2.5-7B-Instruct-GGUF:Q8_0--qwen2" # 可以这样指定Q8_0量化版本，且使用模板
  ];
  registry = "modelscope2ollama-registry.azurewebsites.net";
  # 检查模型是否存在的命令
  checkModel = model: ''
    if ! ${pkgs.ollama}/bin/ollama list | grep -q "${model}"; then
      echo "📥 Pulling Ollama model: ${model}"
      ${pkgs.ollama}/bin/ollama pull "${registry}/${model}"

      # 拉取完成后立即验证
      echo "🔍 验证模型: ${model}"
      model_info=$(${pkgs.ollama}/bin/ollama list | grep "${registry}/${model}")
      # 使用sed提取大小字段（第3列）
      model_size=$(echo "$model_info" | sed 's/ \+/ /g' | cut -d' ' -f3)
      if [ "$model_size" = "0" ] || [ "$model_size" = "0" ] || [ -z "$model_size" ]; then
        echo "❌ 模型下载无效: ${model} (大小: $model_size)"
        echo "🗑️  删除无效模型..."
        ${pkgs.ollama}/bin/ollama rm "${registry}/${model}"
        echo "⚠️  跳过模型 ${model}，继续下一个..."
      else
        echo "✅ 模型验证成功: ${model} (大小: $model_size)"
      fi
    else
      echo "✅ Ollama model already exists: ${model}"
      # 对已存在的模型也进行验证
      echo "🔍 验证已存在的模型: ${model}"
      model_info=$(${pkgs.ollama}/bin/ollama list | grep "${registry}/${model}")
      # 使用sed提取大小字段（第3列）
      model_size=$(echo "$model_info" | sed 's/ \+/ /g' | cut -d' ' -f3)
      if [ "$model_size" = "0" ] || [ "$model_size" = "0" ] || [ -z "$model_size" ]; then
        echo "❌ 已存在的模型无效: ${model} (大小: $model_size)"
        echo "🗑️  删除无效模型..."
        ${pkgs.ollama}/bin/ollama rm "${registry}/${model}"
        echo "⚠️  跳过模型 ${model}，继续下一个..."
      else
        echo "✅ 已存在的模型验证成功: ${model} (大小: $model_size)"
      fi
    fi
  '';
  # 为所有模型生成检查脚本
  checkModelsScript = lib.concatMapStringsSep "\n" checkModel models;
in
{
  # 如果可用，启用 Ollama 系统服务（NixOS 模块）
  # 注意：此模块可能仅在 NixOS 中可用，在 home-manager 中可能不可用
  # services.ollama = {
  #   enable = true;
  #   models = models;
  # };

  # 安装 ollama 命令行工具
  home.packages = with pkgs; [
    ollama
  ];
  home.sessionVariables = {
    OLLAMA_HOST = "127.0.0.1:11434";
    OLLAMA_MODELS = "${config.home.homeDirectory}/.ollama/models";
    # 启用GPU
    OLLAMA_GPU_LAYER = "cuda";
    # OLLAMA_GPU_LAYER = "rocm";
  };
  # 在 home-manager 激活时拉取模型（如果尚未拉取）
  home.activation.pullOllamaModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "🔍 Checking Ollama models..."

    # 检查 ollama 服务是否正在运行
    echo "🔍 Checking ollama service status..."
    if ! ${pkgs.ollama}/bin/ollama list >/dev/null 2>&1; then
      echo "⚠️  Ollama service is not running. Starting ollama serve..."
      # 启动 ollama serve 作为后台进程
      ${pkgs.ollama}/bin/ollama serve &
      OLLAMA_PID=$!
      echo "🔄 Started ollama serve with PID $OLLAMA_PID"

      # 等待服务准备就绪，最多重试10次，每次1秒
      max_retries=10
      retry_count=0
      while [ $retry_count -lt $max_retries ]; do
        if ${pkgs.ollama}/bin/ollama list >/dev/null 2>&1; then
          echo "✅ Ollama service is now ready!"
          break
        fi
        retry_count=$((retry_count + 1))
        echo "   Waiting for ollama service... ($retry_count/$max_retries)"
        sleep 1
      done

      if [ $retry_count -eq $max_retries ]; then
        echo "❌ Failed to start ollama service after $max_retries seconds"
        echo "   Please run 'ollama serve' manually and check logs"
        exit 1
      fi
    else
      echo "✅ Ollama service is already running"
    fi


    # 现在检查模型
    ${checkModelsScript}
    echo "🎉 Ollama models ready!"
  '';

  # 添加ollama相关的shell别名
  programs.bash.shellAliases = lib.mkIf config.programs.bash.enable {
    ollama = "${pkgs.ollama}/bin/ollama";
  };

  # 为zsh也设置别名
  programs.zsh.shellAliases = lib.mkIf config.programs.zsh.enable {
    ollama = "${pkgs.ollama}/bin/ollama";
  };
}
