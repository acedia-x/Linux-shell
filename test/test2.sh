#!/bin/bash

read -p "硬盘名称：" name
Use=$( df -hT | awk -v m="$name" '$7==m {print $6+0}')
if [ -z "$Use" ]; then
        echo "硬盘名有误"
else
	if [ "$Use" -gt 70 ]; then
		echo "警告"
	else
		echo "正常"
	fi
fi
