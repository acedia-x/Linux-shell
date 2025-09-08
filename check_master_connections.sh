#!/bin/bash

CONNECTIONS=$(mysql -uroot -pWWW.1.com -h 2> /dev/null -e "SHOW STATUS LIKE 'Threads_connected'" | awk 'NR==2 {print $2}' )
if [ "$CONNECTIONS" -gt 10 ]; then
    echo "警告"
else
    echo "正常"
fi
