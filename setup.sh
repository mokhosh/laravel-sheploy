#!/bin/bash

# disable interactions on ubuntu 22
export DEBIAN_FRONTEND=noninteractive

# get the ip of the server
IP=$(hostname -I)
IP=${IP%% *}
echo "IP Address of this server: $IP"

# get the public ssh key from user
echo "Enter your public ssh key:"
read -r CLIENT_KEY

# get the public ssh key from user
echo "Enter your project's folder name:"
read -r ROOT

# get the password from user
echo "Enter a secure password (this will be used for mysql and other services):"
read -r PASSWORD

# get the php version from user
echo "Enter your desired php version (default 8.3):"
read -r PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.3}

# get the domain name from user
echo "Enter your domain name:"
read -r DOMAIN

# put the public key in root authorized keys
cd ~/.ssh || exit
echo "$CLIENT_KEY" >> authorized_keys

#create git user
ENC_PASSWORD=$(perl -e 'print crypt($ARGV[0], "password")' "$PASSWORD")
useradd -m -p "$ENC_PASSWORD" git
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
  --execute="CREATE USER '${ROOT}user'@'localhost' IDENTIFIED BY '$PASSWORD';"
mysql \
  --user="root" \
  --password="$PASSWORD" \
  --execute="GRANT ALL ON $ROOT.* TO '${ROOT}user'@'localhost';"
mysql \
  --user="root" \
  --password="$PASSWORD" \
  --execute="FLUSH PRIVILEGES;"

apt install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt update
apt install php"$PHP_VERSION"-\
{fpm,common,mysql,xml,xmlrpc,\
curl,gd,imagick,cli,intl,dev,\
imap,mbstring,opcache,soap,zip} unzip -y

sed -i 's/.*upload_max_filesize.*/upload_max_filesize = 1024M/' /etc/php/"$PHP_VERSION"/fpm/php.ini
sed -i 's/.*post_max_size.*/post_max_size = 1024M/' /etc/php/"$PHP_VERSION"/fpm/php.ini
sed -i 's/.*memory_limit.*/memory_limit = 256M/' /etc/php/"$PHP_VERSION"/fpm/php.ini
sed -i 's/.*max_execution_time.*/max_execution_time = 1000/' /etc/php/"$PHP_VERSION"/fpm/php.ini
sed -i 's/.*max_input_vars.*/max_input_vars = 3000/' /etc/php/"$PHP_VERSION"/fpm/php.ini
sed -i 's/.*max_input_time.*/max_input_time = 1000/' /etc/php/"$PHP_VERSION"/fpm/php.ini

service php"$PHP_VERSION"-fpm restart

cat > /etc/nginx/sites-available/"$DOMAIN" << EOF
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

ln -s /etc/nginx/sites-available/"$DOMAIN" /etc/nginx/sites-enabled/
unlink /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

apt install redis-server -y
sed -i 's/.*supervised no.*/supervised systemd/' /etc/redis/redis.conf
ESCAPED_PASS=${PASSWORD//&/\\&}
sed -i "s/.*requirepass foobared.*/requirepass $ESCAPED_PASS/" /etc/redis/redis.conf
systemctl restart redis.service
printf "\n" | pecl install redis
apt install php-redis -y
sed -i 's/.*extension=redis.so.*/extension=redis.so/' /etc/php/"$PHP_VERSION"/cli/conf.d/20-redis.ini
service php"$PHP_VERSION"-fpm reload

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

# set up snap
apt install libsquashfuse0 squashfuse fuse snapd -y
snap install core; snap refresh core

# set up node and npm
snap install node --classic --channel=18

# set up git
cd /var/www/html || exit
mkdir "$ROOT"
chown git:www-data "$ROOT" -R

apt install git -y
sudo -H -u git bash <<EOFF
cd ~ || exit
git init --bare $ROOT.git
cd ~/$ROOT.git/hooks || exit
touch post-receive
chmod +x post-receive

cat > post-receive << EOF
#!/bin/bash

PROD="/var/www/html/$ROOT"
REPO="/home/git/$ROOT.git"

git --work-tree=\\\$PROD --git-dir=\\\$REPO checkout main -f

cd \\\$PROD || exit
php artisan down
composer install --no-dev --no-interaction
npm install
npm run build
if ! [ -f .env ]
then
    cp .env.example .env
    sed -i 's/.*APP_ENV.*/APP_ENV=production/' .env
    sed -i 's/.*APP_DEBUG.*/APP_DEBUG=false/' .env
    sed -i "s/.*APP_URL.*/APP_URL=https:\/\/$DOMAIN/" .env
    sed -i "s/http:\/\/localhost/https:\/\/$DOMAIN/" .env
    sed -i "s/.*DB_DATABASE.*/DB_DATABASE=$ROOT/" .env
    sed -i "s/.*DB_USERNAME.*/DB_USERNAME=${ROOT}user/" .env
    sed -i "s/.*DB_PASSWORD.*/DB_PASSWORD=\"$PASSWORD\"/" .env
    sed -i "s/.*REDIS_PASSWORD.*/REDIS_PASSWORD=\"$PASSWORD\"/" .env
    php artisan key:generate
fi
php artisan horizon:terminate
php artisan migrate --force
php artisan auth:clear-resets
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan view:cache
php artisan config:cache
php artisan up

EOF
EOFF

# install laravel application
echo "Use either of these commands to add the remote git to your local repo:"
echo "git remote add production git@$IP:$ROOT.git"
echo "git remote add production git@$DOMAIN:$ROOT.git"
echo "And then push your code to production:"
echo "git push production main"
read -r -p 'Push your laravel application to the server and press Enter to continue...' _

cd /var/www/html/"$ROOT" || exit
chgrp -R www-data storage bootstrap/cache vendor
chmod -R ug+rwx storage bootstrap/cache vendor
php artisan storage:link

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

# restart horizon every hour to avoid memory leaks
crontab -l > horizon_cron
echo "0 * * * * cd /var/www/html/$ROOT && php artisan horizon:terminate" >> horizon_cron
crontab horizon_cron
rm horizon_cron

# setup schedule
apt install cron -y
systemctl enable cron

crontab -l > schedule_cron
echo "* * * * * cd /var/www/html/$ROOT && php artisan schedule:run >> /dev/null 2>&1" >> schedule_cron
crontab schedule_cron
rm schedule_cron

# setup ssl
apt remove certbot -y
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
certbot --nginx
certbot renew --dry-run
