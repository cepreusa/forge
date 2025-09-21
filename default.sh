# =========================================
# Переменные
# =========================================
UBUNTU_HOME="/home/ubuntu"
FORGE_DIR="${UBUNTU_HOME}/stable-diffusion-webui-forge"
VENV_DIR="${UBUNTU_HOME}/venv"
LOG_DIR="/var/log/forge"
SUPERVISOR_CONF="/etc/supervisor/conf.d/forge.conf"

APT_PACKAGES=(
    git
    bc
    software-properties-common
)

EXTENSIONS=(
    "https://github.com/zixaphir/Stable-Diffusion-Webui-Civitai-Helper.git"
    "https://github.com/AUTOMATIC1111/stable-diffusion-webui-rembg.git"
    "https://github.com/Coyote-A/ultimate-upscale-for-automatic1111.git"
)

CHECKPOINT_MODELS=(
    "https://huggingface.co/ZhenyaYang/flux_1_dev_hyper_8steps_nf4/resolve/main/flux_1_dev_hyper_8steps_nf4.safetensors"
)

ESRGAN_MODELS=(
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
)

CONFIG_FILES=(
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/config.json"
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/styles_integrated.csv"
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/ui-config.json"
)

# =========================================
# Основные функции
# =========================================

provisioning_print_header() {
    echo "##############################################"
    echo "# Starting Forge provisioning..."
    echo "##############################################"
}

provisioning_print_end() {
    echo "##############################################"
    echo "# Provisioning complete! Forge is ready."
    echo "# Logs: ${LOG_DIR}/forge.log and ${LOG_DIR}/forge.err"
    echo "##############################################"
}

# Создание пользователя ubuntu, если его нет
provisioning_create_ubuntu_user() {
    echo "Проверяем права пользователя ubuntu..."

    # Проверяем, существует ли пользователь
    if id ubuntu &>/dev/null; then
        echo "Пользователь ubuntu найден."
        
        # Проверяем, состоит ли он в группе sudo
        if id -nG ubuntu | grep -qw "sudo"; then
            echo "У пользователя ubuntu уже есть права sudo. Пропускаем настройку."
        else
            echo "Добавляем ubuntu в группу sudo..."
            usermod -aG sudo ubuntu
        fi

        # Создаём sudoers-файл для работы без пароля
        if [[ ! -f /etc/sudoers.d/90-ubuntu ]]; then
            echo "Создаём /etc/sudoers.d/90-ubuntu..."
            echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-ubuntu
            chmod 440 /etc/sudoers.d/90-ubuntu
        fi
    else
        echo "Пользователь ubuntu не найден. Создаём нового..."
        adduser --disabled-password --gecos "" ubuntu
        usermod -aG sudo ubuntu
        echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-ubuntu
        chmod 440 /etc/sudoers.d/90-ubuntu
    fi
}

# Установка системных пакетов
provisioning_get_apt_packages() {
    echo "Устанавливаем системные пакеты..."
    apt-get update
    apt-get install -y "${APT_PACKAGES[@]}"
}

# Установка Python 3.10
provisioning_install_python() {
    echo "Устанавливаем Python 3.10..."
    add-apt-repository ppa:deadsnakes/ppa -y
    apt-get update
    apt-get install -y python3.10 python3.10-venv
}

# Создание виртуального окружения
provisioning_setup_venv() {
    if [[ ! -d "${VENV_DIR}" ]]; then
        echo "Создаём виртуальное окружение..."
        sudo -u ubuntu python3.10 -m venv "${VENV_DIR}"
    else
        echo "Виртуальное окружение уже существует."
    fi
}

# Клонирование Forge
provisioning_clone_forge() {
    if [[ ! -d "${FORGE_DIR}" ]]; then
        echo "Клонируем Forge..."
        sudo -u ubuntu git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git "${FORGE_DIR}"
    else
        echo "Forge уже существует, пропускаем."
    fi
}

# Загрузка extensions
provisioning_get_extensions() {
    sudo -u ubuntu mkdir -p "${FORGE_DIR}/extensions"
    for repo in "${EXTENSIONS[@]}"; do
        dir="${repo##*/}"
        target="${FORGE_DIR}/extensions/${dir}"
        if [[ ! -d "$target" ]]; then
            echo "Скачиваем расширение: $repo"
            sudo -u ubuntu git clone "$repo" "$target" --recursive
        else
            echo "Расширение ${dir} уже установлено."
        fi
    done
}

# Загрузка моделей
provisioning_get_files() {
    local target_dir="$1"
    shift
    sudo -u ubuntu mkdir -p "$target_dir"
    for url in "$@"; do
        filename=$(basename "$url")
        if [[ ! -f "${target_dir}/${filename}" ]]; then
            echo "Скачиваем $filename..."
            sudo -u ubuntu wget -qnc --content-disposition --show-progress -P "$target_dir" "$url"
        else
            echo "$filename уже существует."
        fi
    done
}

# Настройка Supervisor для управления Forge
provisioning_setup_supervisor() {
    echo "Настраиваем Supervisor для Forge..."
    
    # Создаем директорию для логов
    mkdir -p "$LOG_DIR"

    # Генерируем конфиг Supervisor
    cat > "$SUPERVISOR_CONF" <<EOL
[program:forge]
directory=/home/ubuntu/stable-diffusion-webui-forge
command=/usr/bin/env bash -c '/home/ubuntu/stable-diffusion-webui-forge/webui.sh \
--api \
--disable-safe-unpickle \
--enable-insecure-extension-access \
--no-download-sd-model \
--no-half-vae \
--cuda-malloc \
--api-auth $FORGE_AUTH_USER:$FORGE_AUTH_PASS \
--gradio-auth $FORGE_AUTH_USER:$FORGE_AUTH_PASS \
--listen \
--port 17860'
autostart=true
autorestart=true
startsecs=15
startretries=3
stdout_logfile=/var/log/forge/forge.log
stderr_logfile=/var/log/forge/forge.err
stopsignal=TERM
user=ubuntu
environment=U2NET_HOME="/home/ubuntu/.u2net",MPLCONFIGDIR="/home/ubuntu/.config/matplotlib"
EOL

    # Обновляем Supervisor и запускаем Forge
    supervisorctl reread
    supervisorctl update

     Если Forge уже запущен — просто сообщить об этом
    if supervisorctl status forge | grep -q "RUNNING"; then
        echo "Forge уже запущен Supervisor-ом."
    fi

     # Проверяем, с какими параметрами реально запущен Forge
    echo "----------------------------------------" | tee -a /var/log/forge/startup_params.log
    echo "Forge startup parameters (ps output):" | tee -a /var/log/forge/startup_params.log
    ps -ef | grep webui.sh | grep -v grep | tee -a /var/log/forge/startup_params.log
    echo "----------------------------------------" | tee -a /var/log/forge/startup_params.log
}


# =========================================
# Основной процесс
# =========================================
provisioning_start() {
    provisioning_print_header
    provisioning_create_ubuntu_user
    provisioning_get_apt_packages
    provisioning_install_python
    provisioning_setup_venv
    provisioning_clone_forge
    provisioning_get_extensions
    provisioning_get_files "${FORGE_DIR}/models/Stable-diffusion" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${FORGE_DIR}/models/ESRGAN" "${ESRGAN_MODELS[@]}"
    provisioning_get_files "${FORGE_DIR}" "${CONFIG_FILES[@]}"
    provisioning_setup_supervisor
    provisioning_print_end
}

# =========================================
# Запуск provisioning
# =========================================
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
