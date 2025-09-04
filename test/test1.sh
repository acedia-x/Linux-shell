#!/bin/bash

read -p "系统名：" name
if [ "$name" == "linux" ]; then
	echo "红帽"
elif [ "$name" == "windows" ]; then
	echo "微软"
elif [ "$name" == "macos" ]; then
	echo "苹果"
else 
	echo "其他"
fi
