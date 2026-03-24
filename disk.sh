#!/bin/bash

# 获取所有磁盘（类型为 disk）的信息，包括名称、大小、型号
mapfile -t disks < <(lsblk -d -o NAME,TYPE,SIZE,MODEL -n 2>/dev/null | awk '$2=="disk" {print $1,$3,$4}')

# 如果没有找到磁盘，退出
if [ ${#disks[@]} -eq 0 ]; then
    echo "未检测到任何硬盘。"
    exit 1
fi

# 显示菜单
echo "可用的硬盘："
lsblk
for i in "${!disks[@]}"; do
    # 提取信息：名称、大小、型号
    read -r name size model <<< "${disks[$i]}"
    echo "$((i+1))) /dev/$name - $size - ${model:-未知型号}"
done

# 读取用户选择
read -p "请选择硬盘（输入编号）： " choice

# 验证输入是否为数字且在有效范围内
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#disks[@]} ]; then
    echo "无效的选择。"
    exit 1
fi

# 获取所选硬盘的名称
selected_name=$(echo "${disks[$((choice-1))]}" | awk '{print $1}')
selected_disk="/dev/$selected_name"

echo "您选择了：$selected_disk"
# 这里可以根据需要执行后续操作，例如挂载、格式化等