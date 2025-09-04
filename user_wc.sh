#!/bin/bash
bash_count=0
nologin_count=0

wc=$(wc -l < /etc/passwd)

for line in $(cat /etc/passwd); do
    if [[ $line == *bash ]]; then
        let bash_count++
    elif [[ $line == *nologin ]]; then
        ((nologin_count++))
    fi
done

echo "文件总行数: $wc"
echo "bash 用户数: $bash_count"
echo "nologin 用户数: $nologin_count"

