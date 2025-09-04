#!/bin/bash

if [ "$#" -eq 0 ];then
	echo "Help: $0 <linux|windows|macos>"
	exit 0
fi

case $1 in
	linux|Linux)
	echo "红帽"
	;;
	windows|Windows)
	echo "微软"
	;;
	macos|Macos)
	echo "苹果"
	;;
	*)
	echo "其他"
	;;
esac
