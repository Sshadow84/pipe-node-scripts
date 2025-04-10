#!/bin/bash

# Цвета для оформления текста в терминале
CLR_INFO='\033[1;97;44m'    # Белый на синем - для информации
CLR_SUCCESS='\033[1;30;42m'  # Чёрный на зелёном - для успеха
CLR_WARNING='\033[1;37;41m'  # Белый на красном - для предупреждений
CLR_ERROR='\033[1;31;40m'    # Красный на чёрном - для ошибок
CLR_GREEN='\033[1;32m'       # Зелёный - для пунктов меню
CLR_RESET='\033[0m'          # Сброс цветов

# Путь к файлу конфигурации
CONFIG_FILE="$HOME/pipe/config.sh"
# Путь для глобальной установки pop
POP_PATH="/usr/local/bin/pop"
# Имя службы systemd
SERVICE_NAME="pipe-node.service"

# Функция отображения логотипа
function show_logo() {
    echo -e "${CLR_INFO}      Добро пожаловать в скрипт управления нодой Pipe Network      ${CLR_RESET}"
    echo -e "${CLR_GREEN}--------------------------------------------------${CLR_RESET}"
    echo -e "${CLR_GREEN}|       Pipe Network Node Manager by Sshadow84  |${CLR_RESET}"
    echo -e "${CLR_GREEN}--------------------------------------------------${CLR_RESET}"
}

# Установка необходимых зависимостей с проверкой
function install_dependencies() {
    echo -e "${CLR_INFO}▶ Обновляем систему и устанавливаем зависимости...${CLR_RESET}"
    sudo apt update
    for pkg in curl ufw libcap2-bin; do
        if ! dpkg -l | grep -q $pkg; then
            sudo apt install -y $pkg || { echo -e "${CLR_ERROR}Ошибка установки $pkg${CLR_RESET}"; exit 1; }
        fi
    done
    echo -e "${CLR_SUCCESS}✅ Зависимости установлены!${CLR_RESET}"
}

# Проверка и освобождение портов
function free_ports() {
    echo -e "${CLR_INFO}▶ Освобождаем порты 80, 443, 8003...${CLR_RESET}"
    for port in 80 443 8003; do
        if sudo lsof -i :$port > /dev/null 2>&1; then
            sudo lsof -i :$port | awk 'NR>1 {print $2}' | xargs -r sudo kill -9
            echo -e "${CLR_SUCCESS}Порт $port очищен${CLR_RESET}"
        else
            echo -e "${CLR_INFO}Порт $port уже свободен${CLR_RESET}"
        fi
    done
}

# Установка, регистрация и запуск ноды Pipe
function install_and_setup_node() {
    echo -e "${CLR_INFO}▶ Установка и настройка ноды Pipe...${CLR_RESET}"
    mkdir -p $HOME/pipe/pipe_cache
    cd $HOME/pipe

    # Очистка старого pop и портов
    sudo rm -f $POP_PATH
    free_ports

    # Скачивание и настройка pop v0.2.8
    sudo curl -L -o $POP_PATH https://dl.pipecdn.app/v0.2.8/pop || { echo -e "${CLR_ERROR}Ошибка скачивания pop${CLR_RESET}"; exit 1; }
    sudo chmod +x $POP_PATH
    sudo setcap 'cap_net_bind_service=+ep' $POP_PATH

    # Открытие портов через ufw
    echo -e "${CLR_INFO}▶ Открытие портов 80, 443, 8003 через UFW...${CLR_RESET}"
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 8003/tcp
    sudo ufw reload

    # Запрос параметров с проверкой
    read -p "Введите RAM для ноды (в ГБ, например, 4): " RAM
    [ -z "$RAM" ] && RAM=4
    read -p "Введите макс. объём диска (в ГБ, например, 100): " DISK
    [ -z "$DISK" ] && DISK=100
    read -p "Введите ваш Solana кошелёк (pubKey): " WALLET_KEY
    [ -z "$WALLET_KEY" ] && { echo -e "${CLR_ERROR}Ошибка: кошелёк обязателен${CLR_RESET}"; return 1; }
    echo "RAM=$RAM" > "$CONFIG_FILE"
    echo "DISK=$DISK" >> "$CONFIG_FILE"
    echo "WALLET_KEY=\"$WALLET_KEY\"" >> "$CONFIG_FILE"
    echo -e "${CLR_SUCCESS}✅ Параметры сохранены в $CONFIG_FILE${CLR_RESET}"

    # Регистрация
    read -p "Введите реферальный код (или Enter для пропуска): " REF_CODE
    if [ -n "$REF_CODE" ]; then
        sudo $POP_PATH --signup-by-referral-route "$REF_CODE" || echo -e "${CLR_WARNING}⚠ Ошибка регистрации, продолжаем без реферального кода${CLR_RESET}"
    fi
    echo -e "${CLR_SUCCESS}✅ Настройка ноды завершена!${CLR_RESET}"

    # Создание службы
    sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null <<EOF
[Unit]
Description=Pipe Network Node
After=network.target

[Service]
ExecStart=$POP_PATH --ram $RAM --max-disk $DISK --cache-dir $HOME/pipe/pipe_cache --pubKey "$WALLET_KEY" --enable-80-443
Restart=always
RestartSec=5
User=$USER
LimitNOFILE=65535
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME

    # Запуск службы с проверкой портов
    echo -e "${CLR_INFO}▶ Запуск службы...${CLR_RESET}"
    sudo systemctl start $SERVICE_NAME || { echo -e "${CLR_ERROR}Ошибка запуска службы${CLR_RESET}"; return 1; }
    sleep 30

    # Проверка портов
    echo -e "${CLR_INFO}▶ Проверка портов 80, 443, 8003...${CLR_RESET}"
    sudo ss -tuln | grep -E '80|443|8003' || echo -e "${CLR_WARNING}⚠ Порты не найдены в списке активных${CLR_RESET}"
    if sudo ss -tuln | grep -q '8003.*LISTEN'; then
        echo -e "${CLR_SUCCESS}✅ Порт 8003 активен! Нода запущена.${CLR_RESET}"
        if ! sudo ss -tuln | grep -qE '80.*LISTEN|443.*LISTEN'; then
            echo -e "${CLR_WARNING}⚠ Порты 80 и 443 не активны. Возможно, флаг --enable-80-443 не работает или требует внешнего подключения.${CLR_RESET}"
        fi
        if sudo journalctl -u $SERVICE_NAME -n 20 | grep -q "No UPnP-enabled router found"; then
            echo -e "${CLR_WARNING}⚠ Требуется ручной проброс порта 8003. Инструкции:${CLR_RESET}"
            echo -e "  1. Войдите в настройки роутера или панель управления сервером."
            echo -e "  2. Настройте проброс: Внешний порт 8003 → Внутренний порт 8003, TCP."
            echo -e "  3. Опционально: добавьте порты 80 и 443."
        fi
    else
        echo -e "${CLR_WARNING}⚠ Порт 8003 не активен, перезапуск службы...${CLR_RESET}"
        sudo systemctl stop $SERVICE_NAME
        free_ports
        sudo systemctl start $SERVICE_NAME
        sleep 30
        sudo ss -tuln | grep -E '80|443|8003' || echo -e "${CLR_WARNING}⚠ Порты не найдены в списке активных${CLR_RESET}"
        if sudo ss -tuln | grep -q '8003.*LISTEN'; then
            echo -e "${CLR_SUCCESS}✅ Порт 8003 активен! Нода запущена.${CLR_RESET}"
        else
            echo -e "${CLR_ERROR}Ошибка: порт 8003 не слушается! Логи службы:${CLR_RESET}"
            sudo journalctl -u $SERVICE_NAME -n 20
            return 1
        fi
    fi
}

# Проверка статуса ноды
function check_status() {
    echo -e "${CLR_INFO}▶ Проверка метрик ноды...${CLR_RESET}"
    cd $HOME/pipe && $POP_PATH --status
}

# Проверка заработанных поинтов
function check_points() {
    echo -e "${CLR_INFO}▶ Проверка заработанных поинтов...${CLR_RESET}"
    cd $HOME/pipe && $POP_PATH --points
}

# Генерация реферального кода
function generate_referral() {
    echo -e "${CLR_INFO}▶ Генерация реферального кода...${CLR_RESET}"
    cd $HOME/pipe && $POP_PATH --gen-referral-route
}

# Создание резервной копии node_info.json
function backup_node_info() {
    if [ -f "$HOME/pipe/node_info.json" ]; then
        cp $HOME/pipe/node_info.json $HOME/pipe/node_info_backup_$(date +%F_%T).json
        echo -e "${CLR_SUCCESS}✅ Копия node_info.json создана: $HOME/pipe/node_info_backup_$(date +%F_%T).json${CLR_RESET}"
    else
        echo -e "${CLR_WARNING}⚠ Файл node_info.json не найден в $HOME/pipe${CLR_RESET}"
    fi
}

# Обновление портов и службы
function refresh_ports() {
    echo -e "${CLR_INFO}▶ Обновление портов и службы...${CLR_RESET}"
    # Остановка и удаление старой службы
    sudo systemctl stop $SERVICE_NAME
    sudo rm -f /etc/systemd/system/$SERVICE_NAME
    sudo systemctl daemon-reload

    # Переустановка pop
    echo -e "${CLR_INFO}▶ Переустановка pop v0.2.8...${CLR_RESET}"
    sudo rm -f $POP_PATH
    sudo curl -L -o $POP_PATH https://dl.pipecdn.app/v0.2.8/pop || { echo -e "${CLR_ERROR}Ошибка скачивания pop${CLR_RESET}"; return 1; }
    sudo chmod +x $POP_PATH
    sudo setcap 'cap_net_bind_service=+ep' $POP_PATH

    # Очистка портов
    free_ports

    # Проверка наличия конфигурации
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${CLR_ERROR}Ошибка: файл конфигурации $CONFIG_FILE не найден! Установите ноду через пункт 1.${CLR_RESET}"
        return 1
    fi
    source "$CONFIG_FILE"

    # Пересоздание службы
    echo -e "${CLR_INFO}▶ Создание новой службы...${CLR_RESET}"
    sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null <<EOF
[Unit]
Description=Pipe Network Node
After=network.target

[Service]
ExecStart=$POP_PATH --ram $RAM --max-disk $DISK --cache-dir $HOME/pipe/pipe_cache --pubKey "$WALLET_KEY" --enable-80-443
Restart=always
RestartSec=5
User=$USER
LimitNOFILE=65535
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

    # Запуск службы
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
    sleep 30

    # Проверка портов
    echo -e "${CLR_INFO}▶ Проверка портов 80, 443, 8003...${CLR_RESET}"
    sudo ss -tuln | grep -E '80|443|8003' || echo -e "${CLR_WARNING}⚠ Порты не найдены в списке активных${CLR_RESET}"
    if sudo ss -tuln | grep -q '8003.*LISTEN'; then
        echo -e "${CLR_SUCCESS}✅ Порт 8003 активен! Нода запущена.${CLR_RESET}"
        if ! sudo ss -tuln | grep -qE '80.*LISTEN|443.*LISTEN'; then
            echo -e "${CLR_WARNING}⚠ Порты 80 и 443 не активны. Возможно, флаг --enable-80-443 не работает или требует внешнего подключения.${CLR_RESET}"
        fi
        if sudo journalctl -u $SERVICE_NAME -n 20 | grep -q "No UPnP-enabled router found"; then
            echo -e "${CLR_WARNING}⚠ Требуется ручной проброс порта 8003. Инструкции:${CLR_RESET}"
            echo -e "  1. Войдите в настройки роутера или панель управления сервером."
            echo -e "  2. Настройте проброс: Внешний порт 8003 → Внутренний порт 8003, TCP."
            echo -e "  3. Опционально: добавьте порты 80 и 443."
        fi
    else
        echo -e "${CLR_WARNING}⚠ Порт 8003 не активен, повторный перезапуск...${CLR_RESET}"
        sudo systemctl stop $SERVICE_NAME
        free_ports
        sudo systemctl start $SERVICE_NAME
        sleep 30
        sudo ss -tuln | grep -E '80|443|8003' || echo -e "${CLR_WARNING}⚠ Порты не найдены в списке активных${CLR_RESET}"
        if sudo ss -tuln | grep -q '8003.*LISTEN'; then
            echo -e "${CLR_SUCCESS}✅ Порт 8003 активен! Нода запущена.${CLR_RESET}"
        else
            echo -e "${CLR_ERROR}Ошибка: порт 8003 не слушается! Логи службы:${CLR_RESET}"
            sudo journalctl -u $SERVICE_NAME -n 20
            return 1
        fi
    fi
}

# Удаление ноды и её файлов
function remove_node() {
    read -p "⚠ Удалить ноду Pipe? (y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" ]]; then
        echo -e "${CLR_WARNING}▶ Удаление ноды Pipe...${CLR_RESET}"
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl disable $SERVICE_NAME
        sudo rm -f /etc/systemd/system/$SERVICE_NAME
        sudo systemctl daemon-reload
        sudo rm -f $POP_PATH
        rm -rf $HOME/pipe
        echo -e "${CLR_SUCCESS}✅ Нода Pipe удалена!${CLR_RESET}"
    else
        echo -e "${CLR_INFO}▶ Удаление отменено.${CLR_RESET}"
    fi
}

# Проверка текущих параметров RAM и DISK
function check_resources() {
    echo -e "${CLR_INFO}▶ Проверка текущих параметров ресурсов...${CLR_RESET}"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${CLR_SUCCESS}Текущие значения:${CLR_RESET}"
        echo -e "RAM: $RAM ГБ"
        echo -e "DISK: $DISK ГБ"
    else
        echo -e "${CLR_WARNING}⚠ Конфигурационный файл $CONFIG_FILE не найден. Установите ноду через пункт 1.${CLR_RESET}"
    fi
}

# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_GREEN}1) 🚀 Установить и запустить ноду${CLR_RESET