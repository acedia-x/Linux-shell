#!/bin/bash

URL="https://www.baidu.com"

while true; do
  status=$(curl -I "$URL" 2>/dev/null | head -n 1 | awk '{print $2}')
  if [ "$status" -ge 200 -a "$status" -lt 400  ] ; then
      echo "1"
  else
      echo "0"
  fi
  sleep 60
done
