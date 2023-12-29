#!/bin/bash

# get the public ssh key from user
echo "Enter your public ssh key:\n"
read CLIENT_KEY

# put the public key in root authorized keys
cd ~/.ssh
echo $CLIENT_KEY >> authorized_keys

#create git user
adduser git
usermod -aG sudo git
