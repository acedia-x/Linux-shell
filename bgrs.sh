#!/bin/bash

sum=0
while read line; do
    sum=$((sum + line))
done < <( awk '{print $4}' /root/bg)

echo "第4列求和结果: $sum"

while read line; do
	 sed -n '/朝阳/p'
done < /root/bg

