#!/bin/bash
mkdir /etc/yum.repos.d/bachup
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/
mkdir /glance
mount /dev/sr0 /glance
ls /glance
cat <<EOF > /etc/yum.repos.d/cdrom.repo
[cdrom] 
name=Local CDROM
baseurl=file:///glance
enabled=1
gpgcheck=0
EOF
yum clean all
yum makecache
yum install -y vim
