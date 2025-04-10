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