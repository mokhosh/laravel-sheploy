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
ENC_PASSWORD=$(perl -e 'print crypt($ARGV[0], "password")' $PASSWORD)
useradd -m -p $ENC_PASSWORD git
usermod -aG git

# put the public key in git authorized keys
sudo -H -u git bash <<EOF
mkdir ~/.ssh
chmod 700 ~/.ssh
echo $CLIENT_KEY >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
EOF

echo "Your public key is authorized for root and git users"

#install nginx, mysql, php, redis and composer
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
  --execute="CREATE DATABASE $ROOT DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql \
  --user="root" \
  --password="$PASSWORD" \
  --execute="CREATE USER '$ROOTuser'@'localhost' IDENTIFIED BY '$PASSWORD';"
mysql \
  --user="root" \
  --password="$PASSWORD" \
  --execute="GRANT ALL ON $ROOT.* TO '$ROOTuser'@'localhost';"
mysql \
  --user="root" \
  --password="$PASSWORD" \
  --execute="FLUSH PRIVILEGES;"

apt install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt update
apt install php$PHP_VERSION-fpm php$PHP_VERSION-common php$PHP_VERSION-mysql \
    php$PHP_VERSION-xml php$PHP_VERSION-xmlrpc php$PHP_VERSION-curl \
    php$PHP_VERSION-gd php$PHP_VERSION-imagick php$PHP_VERSION-cli php$PHP_VERSION-intl \
    php$PHP_VERSION-dev php$PHP_VERSION-imap php$PHP_VERSION-mbstring \
    php$PHP_VERSION-opcache php$PHP_VERSION-soap php$PHP_VERSION-zip unzip -y

sed -i 's/.*upload_max_filesize.*/upload_max_filesize = 1024M/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i 's/.*post_max_size.*/post_max_size = 1024M/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i 's/.*memory_limit.*/memory_limit = 256M/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i 's/.*max_execution_time.*/max_execution_time = 1000/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i 's/.*max_input_vars.*/max_input_vars = 3000/' /etc/php/$PHP_VERSION/fpm/php.ini
sed -i 's/.*max_input_time.*/max_input_time = 1000/' /etc/php/$PHP_VERSION/fpm/php.ini

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

apt install redis-server -y
sed -i 's/.*supervised no.*/supervised systemd/' /etc/redis/redis.conf
ESCAPED_PASS=$(echo "$PASSWORD" | sed 's/&/\\&/')
sed -i "s/.*requirepass foobared.*/requirepass $ESCAPED_PASS/" /etc/redis/redis.conf
systemctl restart redis.service
printf "\n" | pecl install redis
apt install php-redis -y
sed -i 's/.*extension=redis.so.*/extension=redis.so/' /etc/php/$PHP_VERSION/cli/conf.d/20-redis.ini
service php$PHP_VERSION-fpm reload

EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
    >&2 echo 'ERROR: Invalid installer checksum'
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
rm composer-setup.php

# set up git
cd /var/www/html
mkdir $ROOT
chown git:www-data $ROOT -R

apt install git -y
sudo -H -u git bash <<EOFF
cd ~
git init --bare $ROOT.git
cd ~/$ROOT.git/hooks
touch post-receive
chmod +x post-receive

cat > post-receive << EOF
#!/bin/sh

PROD="/var/www/html/$ROOT"
REPO="/home/git/$ROOT.git"

git --work-tree=\\\$PROD --git-dir=\\\$REPO checkout -f

EOF
EOFF

# install laravel application
read -p 'Push your laravel application to the server and press Enter to continue...' CONTINUE

cd /var/www/html/$ROOT
composer install --no-dev --no-interaction
cp .env.example .env && nano .env
php artisan migrate
php artisan key:generate
chgrp -R www-data storage bootstrap/cache vendor
chmod -R ug+rwx storage bootstrap/cache vendor

# setup queue
apt install supervisor -y
cat > /etc/supervisor/conf.d/horizon.conf << EOF
[program:horizon]
process_name=%(program_name)s
command=php /var/www/html/$ROOT/artisan horizon
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=/var/www/html/$ROOT/horizon.log
stopwaitsecs=3600

EOF

supervisorctl reread
supervisorctl update
supervisorctl start horizon

# setup schedule
apt install cron -y
systemctl enable cron

crontab -l > mycron
echo "* * * * * cd /var/www/html/$ROOT && php artisan schedule:run >> /dev/null 2>&1" >> mycron
crontab mycron
rm mycron

# setup ssl
apt install libsquashfuse0 squashfuse fuse snapd -y
snap install core; snap refresh core
apt remove certbot -y
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
certbot --nginx
certbot renew --dry-run
