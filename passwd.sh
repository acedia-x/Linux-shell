#!/bin/bash
useradd joker
/usr/bin/expect << eof
set timeout 10
spawn passwd joker
expect "密码："
send "123456\\n"
expect "密码："
send "123456\\n"
expect eof
eof

