#!/bin/bash

read -p "文件名称：" file_name
if [ -e "$file_name" ]; then
	if [ -d "$file_name" ]; then
		echo "目录"
	elif [ -f "$file_name" ]; then
		echo "普通文件"
	fi
else 
	echo "不存在"
fi
