{ ... }:

{
  # 使用 pipewire 启用声音
  services.pulseaudio.enable = false; # 禁用 pulseaudio
  security.rtkit.enable = true; # 启用实时音频处理
  services.pipewire = {
    enable = true; # 启用 pipewire 服务
    alsa.enable = true; # 启用 ALSA 支持
    alsa.support32Bit = true; # 支持 32 位 ALSA 应用程序
    pulse.enable = true; # 启用 PulseAudio 兼容性
    # 如果你想使用 JACK 应用程序，请取消注释此行
    # jack.enable = true;

    # 使用示例会话管理器（目前还没有其他打包的会话管理器，所以默认启用，
    # 现在无需在你的配置中重新定义）
    # media-session.enable = true;
  };
}
