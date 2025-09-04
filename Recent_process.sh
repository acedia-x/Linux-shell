#!/bin/bash

ps -eo comm,start | sed '1d' | while read -r comm start; do
    qsjc=$(date -d "$start" +%s 2>/dev/null)
    if [ -z "$qsjc" ]; then
        continue
    fi
    xsjc=$(date +%s)
    ssjc=$((xsjc - 600))
    if [ "$qsjc" -gt "$ssjc" ]; then
        echo "进程 $comm 在最近600秒内启动"
    else
	continue
    fi
done
