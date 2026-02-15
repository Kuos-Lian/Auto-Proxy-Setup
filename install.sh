#!/bin/bash

# *****************************************************************************
# РАБОЧИЙ СКРИПТ: Dante (SOCKS5) + Nginx (SNI Proxy)
# Канал: Котомка Ку́оса (@cotomka_kuosa)
# *****************************************************************************

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции красивого вывода
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_question() { echo -e "${PURPLE}[?]${NC} $1"; }
print_section() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}\n"
}

# Проверка на root
if [[ $EUID -ne 0 ]]; then
   print_error "Запусти от root/"
   exit 1
fi

# Приветствие
clear
print_section "УСТАНОВКА: SOCKS5 + SNI PROXY (Nginx)"
echo -e "${YELLOW}ВНИМАНИЕ:${NC} Будет установлено:"
echo -e "  - Dante (SOCKS5) — порт 1080"
echo -e "  - Nginx (SNI proxy) — порт 443 (только HTTPS)"
echo -e "  - iptables с защитой"
echo ""
read -p "Нажми Enter, чтобы продолжить..." dummy

# -----------------------------------------------------------------------------
# ШАГ 1: Подготовка
# -----------------------------------------------------------------------------
print_section "ШАГ 1: ПОДГОТОВКА СИСТЕМЫ"

apt update
apt upgrade -y
apt install -y curl wget git net-tools iptables-persistent nginx

print_success "Система готова"
sleep 1

# -----------------------------------------------------------------------------
# ШАГ 2: Интерфейс
# -----------------------------------------------------------------------------
print_section "ШАГ 2: ОПРЕДЕЛЕНИЕ ИНТЕРФЕЙСА"

# Пытаемся определить автоматически сет-ой интерфейс
DEFAULT_IF=$(ip route | grep '^default' | awk '{print $5}' | head -1)

if [ -n "$DEFAULT_IF" ]; then
    print_info "Найден интерфейс: ${GREEN}$DEFAULT_IF${NC}"
    EXTERNAL_IF=$DEFAULT_IF
else
    print_warning "Автоопределение не сработало. Вот список:"
    ip link show | grep -E '^[0-9]' | awk '{print $2}' | sed 's/://'
    print_question "Введи имя внешнего интерфейса: "
    read EXTERNAL_IF
fi

print_success "Будем использовать интерфейс: $EXTERNAL_IF"
sleep 1

# -----------------------------------------------------------------------------
# ШАГ 3: Dante (SOCKS5)
# -----------------------------------------------------------------------------
print_section "ШАГ 3: УСТАНОВКА DANTE"

print_info "Устанавливаем Dante..."
apt install -y dante-server

# Авторизация Dante
print_question "Нужна авторизация по паролю для SOCKS5? (y/n, по умолчанию y): "
read USE_AUTH
if [[ ! "$USE_AUTH" =~ ^[Nn]$ ]]; then
    useradd -r -s /bin/false socksuser 2>/dev/null
    print_info "Задай пароль для 'socksuser':"
    passwd socksuser
    AUTH_METHOD="username"
    print_success "Пользователь создан"
else
    AUTH_METHOD="none"
    print_warning "Авторизация отключена"
fi

# Конфиг Dante
cat > /etc/danted.conf <<EOF
# Рабочий конфиг Dante
internal: 0.0.0.0 port = 1080
external: $EXTERNAL_IF
socksmethod: $AUTH_METHOD
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    socksmethod: $AUTH_METHOD
}
EOF

systemctl restart danted
systemctl enable danted

if systemctl is-active --quiet danted; then
    print_success "Dante запущен"
else
    print_error "Dante не запустился. Смотри: journalctl -u danted"
fi

# -----------------------------------------------------------------------------
# ШАГ 4: Nginx (SNI Proxy)
# -----------------------------------------------------------------------------
print_section "ШАГ 4: УСТАНОВКА NGINX SNI PROXY"

# Убеждаемся что модуль stream есть
apt install -y libnginx-mod-stream

# Бэкап
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Конфиг строго по статье с Хабра (https://habr.com/ru/articles/956916/) так что если вдруг че, то можно на Хабре посмотреть коменты
cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

stream {
    log_format proxy '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time "$ssl_preread_server_name"';

    access_log /var/log/nginx/stream-access.log proxy;
    error_log /var/log/nginx/stream-error.log;

    server {
        resolver 8.8.8.8 ipv6=off;
        listen 443;
        ssl_preread on;
        proxy_pass $ssl_preread_server_name:443;
        proxy_connect_timeout 10s;
        proxy_timeout 30s;
    }
}

http {
    access_log off;
    error_log /dev/null crit;
    server {
        listen 127.0.0.1:8080 default_server;
        server_name _;
        return 444;
    }
}
EOF

# Проверка конфига
nginx -t

if [ $? -eq 0 ]; then
    systemctl restart nginx
    systemctl enable nginx
    print_success "Nginx настроен и запущен"
else
    print_error "Конфиг nginx битый. Восстанавливаю бэкап"
    cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
    systemctl restart nginx
fi

# -----------------------------------------------------------------------------
# ШАГ 5: iptables
# -----------------------------------------------------------------------------
print_section "ШАГ 5: НАСТРОЙКА ФАЙЕРВОЛА"

print_question "Порт для SSH? (по умолчанию 22): "
read SSH_PORT
SSH_PORT=${SSH_PORT:-22}

print_question "Ограничить SOCKS5 (1080) по IP? (y/n, по умолчанию n): "
read RESTRICT_SOCKS

# Сброс
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Политики
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Локальное
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# SSH
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
print_success "SSH порт $SSH_PORT открыт"

# SNI Proxy (443)
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
print_success "Порт 443 открыт для всех"

# SOCKS5
if [[ "$RESTRICT_SOCKS" =~ ^[YyДд]$ ]]; then
    print_question "Введи свой IP для доступа к SOCKS5: "
    read SOCKS_ALLOW_IP
    iptables -A INPUT -p tcp --dport 1080 -s $SOCKS_ALLOW_IP -j ACCEPT
    print_success "Порт 1080 доступен только с $SOCKS_ALLOW_IP"
else
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
    print_warning "Порт 1080 открыт для всех"
fi

netfilter-persistent save
print_success "Правила сохранены"

# -----------------------------------------------------------------------------
# ШАГ 6: ФИНАЛ
# -----------------------------------------------------------------------------
print_section "УСТАНОВКА ЗАВЕРШЕНА"

SERVER_IP=$(curl -s ifconfig.me)

echo -e "${GREEN}Твой сервер готов!${NC}"
echo ""
echo -e "${YELLOW}=== DANTE (SOCKS5) ===${NC}"
echo -e "IP: ${CYAN}$SERVER_IP${NC}"
echo -e "Порт: ${CYAN}1080${NC}"
if [[ "$AUTH_METHOD" == "username" ]]; then
    echo -e "Логин: ${CYAN}socksuser${NC}"
    echo -e "Пароль: тот, что вводил, не забудь его"
fi
echo ""
echo -e "${YELLOW}=== NGINX (SNI PROXY) ===${NC}"
echo -e "IP: ${CYAN}$SERVER_IP${NC}"
echo -e "Порт: ${CYAN}443 (только HTTPS)${NC}"
echo -e "${YELLOW}Для hosts файла:${NC}"
echo -e "   ${CYAN}$SERVER_IP    rutracker.org${NC}"
echo -e "   ${CYAN}$SERVER_IP    chatgpt.com${NC}"
echo -e "   ${CYAN}$SERVER_IP    gemini.google.com${NC}"
echo ""
echo -e "${YELLOW}=== ПРОВЕРКА ===${NC}"
echo -e "SOCKS5: ${CYAN}curl --socks5 $SERVER_IP:1080 ifconfig.me${NC}"
echo -e "SNI:    ${CYAN}curl -H 'Host: rutracker.org' https://$SERVER_IP -k -I${NC}"
echo ""
print_success "Скрипт отработал. Если всё работает - прекрасно."
print_success "Если нет - то иди в @cotomka_kuosa и ной."

exit 0
