#!/bin/bash

# get the public ssh key from user
echo "Enter your public ssh key:\n"
read CLIENT_KEY

# get the public ssh key from user
echo "Enter your project's folder name key:\n"
read ROOT

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
