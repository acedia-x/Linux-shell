#!/bin/bash
# 创建数据库和表
mysql -uroot -pWWW.1.com 2> /dev/null <<EOF
CREATE DATABASE IF NOT EXISTS passwd CHARACTER SET utf8;
USE passwd;
CREATE TABLE IF NOT EXISTS users (
  User_identification_Number INT PRIMARY KEY AUTO_INCREMENT,
  Username VARCHAR(255) NOT NULL,
  Password VARCHAR(255),
  Group_identification_number VARCHAR(255),
  Annotation_description VARCHAR(255),
  Home_directory VARCHAR(255),
  Login_Shell VARCHAR(255)
);
EOF
# 读取/etc/passwd文件并插入数据
while IFS=: read -r username password uid gid comment homedir shell; do
    if [ -z "$shell" ]; then
        echo "跳过无效行: $username:$password:$uid:$gid:$comment:$homedir:$shell"
        continue
    fi
    
    username=$(mysql -uroot -pWWW.1.com -e 2> /dev/null "SELECT QUOTE('$username')" | tail -1)
    password=$(mysql -uroot -pWWW.1.com -e 2> /dev/null "SELECT QUOTE('$password')"  | tail -1)
    comment=$(mysql -uroot -pWWW.1.com -e 2> /dev/null "SELECT QUOTE('$comment')" | tail -1)
    homedir=$(mysql -uroot -pWWW.1.com -e 2> /dev/null "SELECT QUOTE('$homedir')" | tail -1)
    shell=$(mysql -uroot -pWWW.1.com -e 2> /dev/null "SELECT QUOTE('$shell')" | tail -1)
    
    # 插入数据到MySQL
    mysql -uroot -pWWW.1.com passwd 2> /dev/null <<EOF
INSERT INTO users (Username, Password, Group_identification_number, Annotation_description, Home_directory, Login_Shell)
VALUES ($username, $password, '$gid', $comment, $homedir, $shell);
EOF
done < /etc/passwd
echo "数据导入完成"
