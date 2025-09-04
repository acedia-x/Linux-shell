#!/bin/bash
# vm_sim.sh 虚拟机创建器

echo "请输入要创建虚拟机数量："
read num

if ! [[ "$num" =~ ^[1-9][0-9]*$ ]]; then
	echo "请输入有效数量："
	exit 1
fi

echo "正在创建 $num 台虚拟机..."
sleep 1

for ((i=1;i<=num;i++));do
	vm_name="VM-$i"
	echo "虚拟机 $vm_name 已创建，状态：启动中..."
	sleep 0.5
	echo "虚拟机 $vm_name 状态：运行中"
done

echo "所有虚拟机创建完成！"
