#!/bin/bash

lis=0
est=0
while read line;do
	state=$(echo $line | awk '{print $6}')
	if [ $state == "LISTEM" ]; then
	let lis++
	elif [ $stat == "ESTABLISHED" ]; then
	let est++
	fi
done < < ( netstat -antp | sed '1,2d' )
echo "$lis,$est"
