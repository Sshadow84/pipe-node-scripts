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

# Установка, регистрация и запуск ноды Pipe
function install_and_setup_node() {
    echo -e "${CLR_INFO}▶ Установка и настройка ноды Pipe...${CLR_RESET}"
    mkdir -p $HOME/pipe/pipe_cache
    cd $HOME/pipe

    # Очистка старого pop и портов
    sudo rm -f $POP_PATH
    for port in 80 443 8003; do
        sudo lsof -i :$port | awk 'NR>1 {print $2}' | xargs -r sudo kill -9
    done

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
    [ -z "$RAM" ] && RAM=4  # Значение по умолчанию, если пусто
    read -p "Введите макс. объём диска (в ГБ, например, 100): " DISK
    [ -z "$DISK" ] && DISK=100  # Значение по умолчанию, если пусто
    read -p "Введите ваш Solana кошелёк (pubKey): " WALLET_KEY
    [ -z "$WALLET_KEY" ] && { echo -e "${CLR_ERROR}Ошибка: кошелёк обязателен${CLR_RESET}"; return 1; }
    echo "RAM=$RAM" > "$CONFIG_FILE"
    echo "DISK=$DISK" >> "$CONFIG_FILE"
    echo "WALLET_KEY=\"$WALLET_KEY\"" >> "$CONFIG_FILE"
    echo -e "${CLR_SUCCESS}✅ Параметры сохранены в $CONFIG_FILE${CLR_RESET}"

    # Регистрация
    read -p "Введите реферальный код (или Enter для пропуска): " REF_CODE
    if [ -n "$REF_CODE" ]; then
        sudo $POP_PATH --signup-by-referral-route "$REF_CODE" || { echo -e "${CLR_ERROR}Ошибка регистрации${CLR_RESET}"; return 1; }
    fi
    echo -e "${CLR_SUCCESS}✅ Регистрация ноды завершена!${CLR_RESET}"

    # Создание службы с явной подстановкой переменных
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

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME || { echo -e "${CLR_ERROR}Ошибка запуска службы${CLR_RESET}"; return 1; }
    echo -e "${CLR_SUCCESS}✅ Нода Pipe запущена через systemd!${CLR_RESET}"

    # Проверка портов
    sleep 5
    echo -e "${CLR_INFO}▶ Проверка портов 80, 443, 8003...${CLR_RESET}"
    if ! sudo ss -tuln | grep -qE '80.*LISTEN|443.*LISTEN|8003.*LISTEN'; then
        echo -e "${CLR_ERROR}Ошибка: порты 80, 443 или 8003 не слушаются!${CLR_RESET}"
        sudo journalctl -u $SERVICE_NAME -n 20
    else
        echo -e "${CLR_SUCCESS}✅ Все порты (80, 443, 8003) активны!${CLR_RESET}"
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

# Обновление ноды до последней версии
function update_node() {
    echo -e "${CLR_INFO}▶ Проверка обновлений...${CLR_RESET}"
    CURRENT_VERSION=$(curl -s https://dl.pipecdn.app/v0.2.8/pop --head | grep -i location | awk '{print $2}')
    echo -e "${CLR_INFO}▶ Текущая версия: v0.2.8, доступная: $CURRENT_VERSION${CLR_RESET}"
    read -p "Обновить ноду? (y/n): " UPDATE_CONFIRM
    if [[ "$UPDATE_CONFIRM" == "y" ]]; then
        sudo systemctl stop $SERVICE_NAME
        cd $HOME/pipe
        sudo curl -L -o $POP_PATH "$CURRENT_VERSION" || { echo -e "${CLR_ERROR}Ошибка обновления${CLR_RESET}"; return 1; }
        sudo chmod +x $POP_PATH
        sudo setcap 'cap_net_bind_service=+ep' $POP_PATH
        sudo systemctl start $SERVICE_NAME
        echo -e "${CLR_SUCCESS}✅ Нода обновлена и перезапущена!${CLR_RESET}"
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

# Главное меню на русском с логической последовательностью
function show_menu() {
    show_logo
    echo -e "${CLR_GREEN}1) 🚀 Установить и запустить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 📊 Проверить статус ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 💰 Проверить поинты${CLR_RESET}"
    echo -e "${CLR_GREEN}4) 🌐 Сгенерировать реферальный код${CLR_RESET}"
    echo -e "${CLR_GREEN}5) 💾 Создать копию node_info.json${CLR_RESET}"
    echo -e "${CLR_GREEN}6) 🔄 Обновить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}7) 🗑️ Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}8) 📈 Проверить параметры RAM и DISK${CLR_RESET}"
    echo -e "${CLR_GREEN}9) ❌ Выйти${CLR_RESET}"
    echo -e "${CLR_INFO}Введите номер действия:${CLR_RESET}"
    read -r choice

    case $choice in
        1) install_dependencies && install_and_setup_node ;;
        2) check_status ;;
        3) check_points ;;
        4) generate_referral ;;
        5) backup_node_info ;;
        6) update_node ;;
        7) remove_node ;;
        8) check_resources ;;
        9) echo -e "${CLR_ERROR}Выход...${CLR_RESET}" ;;
        *) echo -e "${CLR_WARNING}Неверный выбор. Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu