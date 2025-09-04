#!/bin/bash

df -hT | tail -n +2 | while read line; do
    usage=$(echo "$line" | awk '{print $6+0}')
    name=$(echo "$line" | awk '{print $1}')
    total=$(echo "$line" | awk '{print $3}')
    available=$(echo "$line" | awk '{print $5}')
    
    if [ "$usage" -gt 70 ]; then
        echo "硬盘名称：$name, 总容量: $total, 可用容量: $available"
    else
        echo "未找到"
	break
    fi
done
