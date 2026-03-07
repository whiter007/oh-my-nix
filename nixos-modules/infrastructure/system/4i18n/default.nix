{ ... }:

let
  my-local-language = "zh_CN.UTF-8";
in
{
  # 国际化配置
  i18n.defaultLocale = my-local-language; # 设置默认语言环境

  i18n.extraLocalSettings = {
    LC_ADDRESS = my-local-language; # 地址格式
    LC_IDENTIFICATION = my-local-language; # 身份标识
    LC_MEASUREMENT = my-local-language; # 测量单位
    LC_MONETARY = my-local-language; # 货币格式
    LC_NAME = my-local-language; # 姓名格式
    LC_NUMERIC = my-local-language; # 数字格式
    LC_PAPER = my-local-language; # 纸张尺寸
    LC_TELEPHONE = my-local-language; # 电话号码格式
    LC_TIME = my-local-language; # 时间日期格式
  };
}
