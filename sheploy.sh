#!/bin/bash

# get the client public key
# ask to create key if it doesnt exist
echo "Loading your public SSH key...\n"
CLIENT_KEY=$(<~/.ssh/id_rsa.pub)

# get the server ip from user
echo "Enter your remote server's IP adress:\n"
read IP

# download the necessary script to the server
echo "Downloading the scripts on your server ~/laravel-sheploy...\n"
ssh root@$IP << EOF
apt install git -y
cd ~
git clone git@github.com:mokhosh/laravel-sheploy
EOF

# run the server and give interactive control to the user
ssh root@$IP

# done
echo "Thanks for using sheploy :)"

