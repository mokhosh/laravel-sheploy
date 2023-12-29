#!/bin/bash

# get the client public key
echo "Loading your public SSH key..."
CLIENT_KEY=$(<~/.ssh/id_rsa.pub)
echo "Copy this so you can use it while setting up your server"
echo $CLIENT_KEY

# get the server ip from user
echo "Enter your remote server's IP adress:"
read IP

# download the necessary script to the server
echo "Downloading the scripts on your server ~/laravel-sheploy..."
ssh root@$IP << EOF
apt install git -y
cd ~
git clone https://github.com/mokhosh/laravel-sheploy.git
EOF

# run the server and give interactive control to the user
ssh root@$IP

# done
echo "Thanks for using sheploy :)"

