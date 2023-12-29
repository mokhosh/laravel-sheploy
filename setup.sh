#!/bin/bash

# get the public ssh key from user
echo "Enter your public ssh key:"
read CLIENT_KEY

# get the public ssh key from user
echo "Enter your project's folder name:"
read ROOT

# get the password from user
echo "Enter a secure password (this will be used for mysql and other services):"
read PASSWORD

# get the php version from user
echo "Enter your desired php version (default 8.3):"
read PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.3}

# get the domain name from user
echo "Enter your domain name:"
read DOMAIN

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

echo "Your public key is authorized for root and git users"

echo "Installing nginx, mysql, and php"

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
apt install php$PHP_VERSION-fpm php$PHP_VERSION-common php$PHP_VERSION-mysql \
    php$PHP_VERSION-xml php$PHP_VERSION-xmlrpc php$PHP_VERSION-curl \
    php$PHP_VERSION-gd php$PHP_VERSION-imagick php$PHP_VERSION-cli \
    php$PHP_VERSION-dev php$PHP_VERSION-imap php$PHP_VERSION-mbstring \
    php$PHP_VERSION-opcache php$PHP_VERSION-soap php$PHP_VERSION-zip unzip -y

sed -i '' 's/.*upload_max_filesize.*/upload_max_filesize = 1024M/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i '' 's/.*post_max_size.*/post_max_size = 1024M/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i '' 's/.*memory_limit.*/memory_limit = 256M/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i '' 's/.*max_execution_time.*/max_execution_time = 1000/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i '' 's/.*max_input_vars.*/max_input_vars = 3000/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i '' 's/.*max_input_time.*/max_input_time = 1000/' /etc/php/$PHP_VERSION/fpm/php.ini

service php$PHP_VERSION-fpm restart

cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    listen [::]:80;
    
    root /var/www/html/$ROOT/public;
    index index.php index.html index.htm index.nginx-debian.html;
    
    server_name $DOMAIN www.$DOMAIN;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}

EOF

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
unlink /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# set up git
cd /var/www/html
mkdir $ROOT
chown git:www-data $ROOT -R

apt install git
su git
cd ~
git init --bare $ROOT.git
cd ~/$ROOT.git/hooks
touch post-receive
chmod +x post-receive

cat > /etc/nginx/sites-available/$DOMAIN << EOF
#!/bin/sh

PROD="/var/www/html/$ROOT"
REPO="/home/git/$ROOT.git"

git --work-tree=\$PROD --git-dir=\$REPO checkout -f

EOF

# exit git user after config
exit
