#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

echo "=========================================="
echo "    AI Agent 内存优化 - Swap 自动设置工具"
echo "=========================================="

# 1. 检查并处理旧的 Swap
SWAP_PATH="/swap/swapfile"

if [ -f "$SWAP_PATH" ]; then
    echo "检测到已存在 Swap 文件: $SWAP_PATH"
    swapon --show | grep -q "$SWAP_PATH"
    ACTIVE=$?
    
    read -p "是否删除旧的 Swap 并重新创建？(y/n): " confirm
    if [[ "$confirm" == [yY] ]]; then
        echo "正在停用旧的 Swap..."
        [ $ACTIVE -eq 0 ] && swapoff "$SWAP_PATH"
        rm -f "$SWAP_PATH"
        # 清理 fstab 中的旧条目
        sed -i "\|$SWAP_PATH|d" /etc/fstab
        echo "旧 Swap 已清理。"
    else
        echo "操作取消，退出脚本。"
        exit 0
    fi
fi

# 2. 获取用户输入
read -p "请输入要创建的 Swap 大小 (单位 GB，建议 2G 内存机器设置 4 或 8): " swap_size

if ! [[ "$swap_size" =~ ^[0-9]+$ ]]; then
    echo "无效输入！请输入一个正整数。"
    exit 1
fi

# 3. 创建目录
if [ ! -d "/swap" ]; then
    mkdir /swap
    echo "目录 /swap 创建成功！"
fi

# 4. 创建 Swap 文件
echo "正在分配 ${swap_size}GB 空间..."
# 优先使用 fallocate (瞬间完成)
if ! fallocate -l "${swap_size}G" "$SWAP_PATH" 2>/dev/null; then
    echo "fallocate 失败，正在切换至 dd 命令 (请稍候)..."
    # 使用 bs=1M 对低内存机器更友好
    dd if=/dev/zero of="$SWAP_PATH" bs=1M count=$((swap_size * 1024)) status=progress conv=fdatasync
fi

# 5. 设置权限与格式化
echo "设置权限为 600..."
chmod 600 "$SWAP_PATH"

echo "正在格式化 Swap..."
mkswap "$SWAP_PATH"

echo "正在启用 Swap..."
swapon "$SWAP_PATH"

# 6. 设置永久挂载
echo "更新 /etc/fstab..."
if ! grep -q "$SWAP_PATH" /etc/fstab; then
    echo "$SWAP_PATH none swap sw 0 0" >> /etc/fstab
    echo "自动挂载设置成功！"
else
    echo "fstab 条目已存在。"
fi

# 7. 调整虚拟内存参数 (针对 AI Agent 优化)
# 内存小时，适当增加 swappiness 可以让系统更早利用 swap，防止 OOM (内存溢出)
echo "正在优化内核参数 (swappiness)..."
sysctl vm.swappiness=60  # 默认 60 适合大多数情况
# 永久保存参数（可选）
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=60" >> /etc/sysctl.conf
fi

echo "=========================================="
echo "Swap 设置完成！当前内存状态："
free -h
echo "=========================================="
