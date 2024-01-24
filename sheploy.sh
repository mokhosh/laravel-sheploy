#!/bin/bash

# get the server ip from user
echo "Enter your remote server's IP adress:"
read IP

# get the client public key
echo "Copying your public SSH key..."
cat ~/.ssh/id_rsa.pub | pbcopy
echo "Copied your public SSH key, so you can use it while setting up your server"

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

