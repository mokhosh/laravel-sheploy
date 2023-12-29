#!/bin/bash

# get the public ssh key from user
echo "Enter your public ssh key:\n"
read CLIENT_KEY

# get the public ssh key from user
echo "Enter your project's folder name:\n"
read ROOT

# get the password from user
echo "Enter a secure password (this will be used for mysql and other services):\n"
read PASSWORD

# put the public key in root authorized keys
cd ~/.ssh
echo $CLIENT_KEY >> authorized_keys

#create git user
adduser git
usermod -aG sudo git

# put the public key in git authorized keys
su git
mkdir ~/.ssh
chmod 700 ~/.ssh
echo $CLIENT_KEY >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit

echo "Your public key is authorized for root and git users\n"

echo "Installing nginx, mysql, and php\n"

apt update
apt install nginx -y
apt install mysql-server -y

mysql \
  --user="root" \
  --execute="ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$PASSWORD';"
mysql \
  --user="root" \
  --password="$PASSWORD" \
  --execute="FLUSH PRIVILEGES;"

apt install software-properties-common
add-apt-repository ppa:ondrej/php
apt update
apt install php8.3-fpm php8.3-common php8.3-mysql php8.3-xml php8.3-xmlrpc \
    php8.3-curl php8.3-gd php8.3-imagick php8.3-cli php8.3-dev php8.3-imap \
    php8.3-mbstring php8.3-opcache php8.3-soap php8.3-zip unzip -y
