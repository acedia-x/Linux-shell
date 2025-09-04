#!/bin/bash

read -p "用户名:" name
if id "$name" &> /dev/null; then
	echo "用户 $name 存在"
else 
	read -p "密码：" password
	useradd "$name" 
	echo "$password" | passwd --stdin "$name" &> /dev/null
	echo "用户 $name 已创建"
fi
