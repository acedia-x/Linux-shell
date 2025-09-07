#!/bin/bash

for i in {1..254}
do
	{
	ping -c 2 -w 3 -i 0.3 192.168.66.$i > /dev/null
	  	 if [ $? -eq 0 ];then
			echo "192.168.66.$i is yes"
		else
			echo "192.168.66.$i is no"
	fi
	}&
done
wait
