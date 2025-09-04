#!/bin/bash
#

for i in $(seq 300000)
do
   let price=RANDOM%5000
   mysql -uroot -pWWW.1.com -e "create database ds charset utf8" 2> /dev/null
   mysql -uroot -pWWW.1.com -e "create table ds.info(id INT PRIMARY KEY NOT NULL AUTO_INCREMENT, name CHAR(20), price INT)" 2> /dev/null
   mysql -uroot -pWWW.1.com -e "insert into ds.info(name, price) values('Huawei$i', $price)" 2> /dev/null
done
