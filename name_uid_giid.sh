#!/bin/bash

read -p "用户名：" name

if id "$name" &> /dev/null; then
	uid=$(id -u "$name")
	gid=$(id -u "$name")
	if [ "$uid" -eq "$gid" ]; then
		echo "good"
	else
		echo "bad"
	fi
else
	echo "不存在"
fi
