FROM php:5-apache-jessie
LABEL Author="fb0sh <fb0sh@outlook.com>"

COPY index.php /var/www/html/index.php
COPY flag.sh /flag.sh
RUN chmod +x /flag.sh

WORKDIR /var/www/html

# 启动 Apache 并保持前台运行
CMD ["sh", "-c", "/flag.sh && apache2-foreground"]