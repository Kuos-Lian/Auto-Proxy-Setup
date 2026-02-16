#!/bin/bash

# *****************************************************************************
# УПРАВЛЕНИЕ DANTE SOCKS5 (Установка + Менеджмент)
# Канал: Котомка Ку́оса (@cotomka_kuosa)
# Версия: 2.0 (С возможностью перенастройки)
# *****************************************************************************

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

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
   print_error "Запусти от root"
   exit 1
fi

# -----------------------------------------------------------------------------
# Функция определения интерфейса
# -----------------------------------------------------------------------------
detect_interface() {
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        echo "$DEFAULT_IF"
    else
        echo "eth0"  # fallback
    fi
}

# -----------------------------------------------------------------------------
# Функция получения текущего IP
# -----------------------------------------------------------------------------
get_current_ip() {
    # Пробуем получить внешний IP
    EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null)
    if [ -z "$EXTERNAL_IP" ]; then
        # Если не вышло, берем IP интерфейса
        INTERFACE=$(detect_interface)
        EXTERNAL_IP=$(ip -4 addr show $INTERFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    echo "$EXTERNAL_IP"
}

# -----------------------------------------------------------------------------
# Функция генерации конфига Dante
# -----------------------------------------------------------------------------
generate_dante_config() {
    local INTERFACE="$1"
    local AUTH_METHOD="$2"
    local CONFIG_FILE="/etc/danted.conf"

    cat > "$CONFIG_FILE" <<EOF
# Dante SOCKS5 конфиг
internal: 0.0.0.0 port = 1080
external: $INTERFACE
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
    print_success "Конфиг Dante обновлен"
}

# -----------------------------------------------------------------------------
# Функция обновления iptables
# -----------------------------------------------------------------------------
update_iptables() {
    local SSH_PORT="$1"
    local SOCKS_IP="$2"
    local RESTRICT_SOCKS="$3"

    # Сохраняем текущие правила
    iptables-save > /etc/iptables/rules.v4.backup 2>/dev/null

    # Сброс
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X

    # Политики
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Разрешаем локальное
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # SSH
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    print_success "SSH порт $SSH_PORT открыт"

    # SOCKS5
    if [[ "$RESTRICT_SOCKS" =~ ^[Yy]$ ]]; then
        iptables -A INPUT -p tcp --dport 1080 -s $SOCKS_IP -j ACCEPT
        print_success "Порт 1080 доступен только с $SOCKS_IP"
    else
        iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
        print_warning "Порт 1080 открыт для всех"
    fi

    netfilter-persistent save 2>/dev/null
    print_success "Правила iptables сохранены"
}

# -----------------------------------------------------------------------------
# Функция установки
# -----------------------------------------------------------------------------
install_dante() {
    print_section "УСТАНОВКА DANTE SOCKS5"

    # Подготовка
    apt update
    apt install -y dante-server iptables-persistent net-tools curl

    # Интерфейс
    DEFAULT_IF=$(detect_interface)
    print_question "Интерфейс [$DEFAULT_IF]: "
    read EXTERNAL_IF
    EXTERNAL_IF=${EXTERNAL_IF:-$DEFAULT_IF}

    # Авторизация
    print_question "Нужна авторизация по паролю? (Y/n): "
    read USE_AUTH
    if [[ ! "$USE_AUTH" =~ ^[Nn]$ ]]; then
        useradd -r -s /bin/false socksuser 2>/dev/null
        print_info "Пароль для socksuser (Enter = 'sockspass'): "
        read -s USER_PASS
        echo
        USER_PASS=${USER_PASS:-sockspass}
        echo "socksuser:$USER_PASS" | chpasswd
        AUTH_METHOD="username"
        print_success "Пользователь socksuser создан с паролем: $USER_PASS"
    else
        AUTH_METHOD="none"
        print_warning "Авторизация отключена"
    fi

    # Генерация конфига
    generate_dante_config "$EXTERNAL_IF" "$AUTH_METHOD"

    # Запуск
    systemctl restart danted
    systemctl enable danted

    if systemctl is-active --quiet danted; then
        print_success "Dante запущен"
    else
        print_error "Dante не запустился"
        journalctl -u danted --no-pager -n 10
        exit 1
    fi

    # IPTables
    print_question "Порт SSH [22]: "
    read SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    print_question "Ограничить SOCKS5 по IP? (y/N): "
    read RESTRICT_SOCKS
    RESTRICT_SOCKS=${RESTRICT_SOCKS:-N}

    SOCKS_IP=""
    if [[ "$RESTRICT_SOCKS" =~ ^[Yy]$ ]]; then
        CURRENT_IP=$(get_current_ip)
        print_question "Твой IP [$CURRENT_IP]: "
        read SOCKS_IP
        SOCKS_IP=${SOCKS_IP:-$CURRENT_IP}
    fi

    update_iptables "$SSH_PORT" "$SOCKS_IP" "$RESTRICT_SOCKS"

    # Финальный вывод
    SERVER_IP=$(get_current_ip)
    print_section "УСТАНОВКА ЗАВЕРШЕНА"
    echo -e "${GREEN}✅ DANTE SOCKS5 ГОТОВ${NC}"
    echo ""
    echo "IP: $SERVER_IP"
    echo "Port: 1080"
    if [[ "$AUTH_METHOD" == "username" ]]; then
        echo "Login: socksuser"
        echo "Password: $USER_PASS"
    fi
    echo ""
    echo "Проверка:"
    if [[ "$AUTH_METHOD" == "username" ]]; then
        echo "curl --socks5 socksuser:$USER_PASS@$SERVER_IP:1080 ifconfig.me"
    else
        echo "curl --socks5 $SERVER_IP:1080 ifconfig.me"
    fi
}

# -----------------------------------------------------------------------------
# Функция удаления
# -----------------------------------------------------------------------------
uninstall_dante() {
    print_section "УДАЛЕНИЕ DANTE"

    # Останавливаем и удаляем
    systemctl stop danted
    systemctl disable danted
    apt remove -y dante-server
    apt autoremove -y

    # Удаляем конфиги
    rm -f /etc/danted.conf
    rm -f /etc/iptables/rules.v4.backup

    # Сбрасываем iptables
    iptables -F
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    netfilter-persistent save

    # Удаляем пользователя
    userdel -r socksuser 2>/dev/null

    print_success "Dante полностью удален"
}

# -----------------------------------------------------------------------------
# Функция изменения конфигурации
# -----------------------------------------------------------------------------
reconfigure_dante() {
    print_section "ИЗМЕНЕНИЕ КОНФИГУРАЦИИ"

    # Проверяем, установлен ли Dante
    if ! systemctl list-unit-files | grep -q danted; then
        print_error "Dante не установлен. Сначала запусти установку."
        return 1
    fi

    # Текущий интерфейс
    CURRENT_IF=$(grep "^external:" /etc/danted.conf | awk '{print $2}')
    print_info "Текущий интерфейс: $CURRENT_IF"
    print_question "Новый интерфейс [$CURRENT_IF]: "
    read NEW_IF
    NEW_IF=${NEW_IF:-$CURRENT_IF}

    # Текущая авторизация
    if grep -q "socksmethod: username" /etc/danted.conf; then
        CURRENT_AUTH="username"
        print_info "Авторизация: ВКЛЮЧЕНА"
    else
        CURRENT_AUTH="none"
        print_info "Авторизация: ОТКЛЮЧЕНА"
    fi

    print_question "Изменить авторизацию? (y/N): "
    read CHANGE_AUTH
    if [[ "$CHANGE_AUTH" =~ ^[Yy]$ ]]; then
        if [[ "$CURRENT_AUTH" == "username" ]]; then
            # Отключаем авторизацию
            NEW_AUTH="none"
            print_warning "Авторизация будет ОТКЛЮЧЕНА"
        else
            # Включаем авторизацию
            NEW_AUTH="username"
            print_info "Авторизация будет ВКЛЮЧЕНА"
            # Создаем пользователя если нет
            if ! id -u socksuser &>/dev/null; then
                useradd -r -s /bin/false socksuser
                print_info "Пароль для socksuser (Enter = 'sockspass'): "
                read -s USER_PASS
                echo
                USER_PASS=${USER_PASS:-sockspass}
                echo "socksuser:$USER_PASS" | chpasswd
            fi
        fi
    else
        NEW_AUTH="$CURRENT_AUTH"
    fi

    # Обновляем конфиг
    generate_dante_config "$NEW_IF" "$NEW_AUTH"

    # Меняем пароль если нужно
    if [[ "$NEW_AUTH" == "username" ]]; then
        print_question "Изменить пароль socksuser? (y/N): "
        read CHANGE_PASS
        if [[ "$CHANGE_PASS" =~ ^[Yy]$ ]]; then
            print_info "Новый пароль для socksuser:"
            passwd socksuser
        fi
    fi

    # Перезапускаем
    systemctl restart danted
    print_success "Конфигурация обновлена, Dante перезапущен"
}

# -----------------------------------------------------------------------------
# Функция изменения белого IP
# -----------------------------------------------------------------------------
change_whitelist() {
    print_section "ИЗМЕНЕНИЕ БЕЛОГО IP"

    # Проверяем текущие правила
    CURRENT_SOCKS_RULE=$(iptables -L INPUT -n | grep dpt:1080 | head -1)

    if echo "$CURRENT_SOCKS_RULE" | grep -q "s"; then
        CURRENT_IP=$(echo "$CURRENT_SOCKS_RULE" | awk '{print $4}')
        print_info "Текущий белый IP: $CURRENT_IP"
    else
        print_info "Сейчас порт 1080 открыт для всех"
    fi

    print_question "Ограничить по IP? (Y/n): "
    read RESTRICT
    RESTRICT=${RESTRICT:-Y}

    if [[ "$RESTRICT" =~ ^[Yy]$ ]]; then
        CURRENT_IP=$(get_current_ip)
        print_question "Введи IP [$CURRENT_IP]: "
        read NEW_IP
        NEW_IP=${NEW_IP:-$CURRENT_IP}
        update_iptables "$(grep dport22 /etc/iptables/rules.v4 2>/dev/null | grep -o 'dport [0-9]*' | cut -d' ' -f2 | head -1 || echo 22)" "$NEW_IP" "Y"
    else
        update_iptables "$(grep dport22 /etc/iptables/rules.v4 2>/dev/null | grep -o 'dport [0-9]*' | cut -d' ' -f2 | head -1 || echo 22)" "" "N"
    fi
}

# -----------------------------------------------------------------------------
# Главное меню
# -----------------------------------------------------------------------------
while true; do
    print_section "УПРАВЛЕНИЕ DANTE SOCKS5"
    echo "1) Установить Dante"
    echo "2) Удалить Dante"
    echo "3) Изменить конфигурацию (интерфейс/авторизация)"
    echo "4) Изменить белый IP для SOCKS5"
    echo "5) Показать статус"
    echo "6) Перезапустить Dante"
    echo "7) Выход"
    echo ""
    print_question "Выбери действие [1]: "
    read ACTION
    ACTION=${ACTION:-1}

    case $ACTION in
        1) install_dante ;;
        2) 
            print_question "Точно удалить Dante? (y/N): "
            read CONFIRM
            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                uninstall_dante
            fi
            ;;
        3) reconfigure_dante ;;
        4) change_whitelist ;;
        5)
            print_section "СТАТУС"
            systemctl status danted --no-pager -l
            echo ""
            iptables -L INPUT -n | grep -E '(dpt:22|dpt:1080)'
            ;;
        6)
            systemctl restart danted
            print_success "Dante перезапущен"
            ;;
        7) 
            print_success "Выход"
            exit 0
            ;;
        *) print_warning "Неверный выбор" ;;
    esac

    echo ""
    read -p "Нажми Enter, чтобы продолжить..."
done
