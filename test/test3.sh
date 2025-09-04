#!/bin/bash

IO=$(SQL=$(mysql -u root -pWWW.1.com -e "SHOW SLAVE STATUS\G" 2> /dev/null | grep 'Slave_IO_Running:' | cut -d: -f2 | tr -d '[:space:]'))
if [ "$IO" == "yes" ]; then
	echo "1"
else
	echo "0"
fi  
SQL=$(mysql -u root -pWWW.1.com -e "SHOW SLAVE STATUS\G" 2> /dev/null | grep 'Slave_SQL_Running:' | cut -d: -f2 | tr -d '[:space:]')
if [ "${SQL,,}" == "yes" ]; then
        echo "1"
else
        echo "0"
fi  
