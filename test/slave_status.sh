#!/bin/bash


SLAVE_STATUS=$(mysql -uroot -pWWW.1.com 2> /dev/null -e "SHOW SLAVE STATUS\G" 2>/dev/null)

DELAY=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master" | awk '{print $2}')

if [ "$DELAY" = "NULL" ]; then
    echo "未运行"
elif [ "$DELAY" -gt 0 ]; then
    echo "警告 延迟 $DELAY 秒"
else
    echo "无延迟"
fi
