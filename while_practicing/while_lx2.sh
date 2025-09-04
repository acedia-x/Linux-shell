#!/bin/bash

while read line; do
	a=$(grep bash | wc -l)
	b=$(grep nologin | wc -l)
	echo "bash: $a"
	echo "nologin: $b"
done < /etc/passwd
