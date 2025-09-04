#!/bin/bash

read -p "数字：" number

if [ "$number" -ge 100 ]; then
	echo "A"
else
	echo "B"
fi
