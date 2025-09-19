#!/bin/bash

# =========================================
# Пути и директории
# =========================================
FORGE_DIR=${WORKSPACE}/stable-diffusion-webui-forge
LOG_DIR="/var/log/forge"
UBUNTU_HOME="/home/ubuntu"

mkdir -p "$LOG_DIR"

# =========================================
# Пакеты для установки
# =========================================
APT_PACKAGES=(
    git
    wget
    software-properties-common
    python3.10-venv
    supervisor
)

# =========================================
# Extensions
# =========================================
EXTENSIONS=(
    "https://github.com/zixaphir/Stable-Diffusion-Webui-Civitai-Helper.git"
    "https://github.com/AUTOMATIC1111/stable-diffusion-webui-rembg.git"
    "https://github.com/Coyote-A/ultimate-upscale-for-automatic1111.git"
)

# =========================================
# Модели
# =========================================
CHECKPOINT_MODELS=(
    "https://huggingface.co/ZhenyaYang/flux_1_dev_hyper_8steps_nf4/resolve/main/flux_1_dev_hyper_8steps_nf4.safetensors"
)

ESRGAN_MODELS=(
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
)

# =========================================
# Конфиги Forge
# =========================================
CONFIG_FILES=(
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/config.json"
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/styles_integrated.csv"
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/ui-config.json"
)

# =========================================
# Supervisor config path
# =========================================
SUPERVISOR_CONF="/etc/supervisor/conf.d/forge.conf"

# =========================================
# Логирование provisioning
# =========================================
PROVISIONING_LOG="$LOG_DIR/provisioning.log"
exec > >(tee -a "$PROVISIONING_LOG") 2>&1

# =========================================
# Начало provisioning
# =========================================
function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_install_python     
    provisioning_clone_forge
    provisioning_setup_python_venv 
    provisioning_setup_python_venv
    provisioning_get_extensions
    # provisioning_get_files "${FORGE_DIR}/models/Stable-diffusion" "${CHECKPOINT_MODELS[@]}"
    # provisioning_get_files "${FORGE_DIR}/models/ESRGAN" "${ESRGAN_MODELS[@]}"
    provisioning_get_files "${FORGE_DIR}" "${CONFIG_FILES[@]}"

    # Avoid git errors because we run as root but files are owned by 'user'
    export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
    git config --file $GIT_CONFIG_GLOBAL --add safe.directory '*'
    
    provisioning_setup_supervisor
    provisioning_restart_supervisor
    provisioning_print_end
}

# =========================================
# Установка пакетов
# =========================================
function provisioning_get_apt_packages() {
    echo "Устанавливаем системные пакеты..."
    apt-get update
    apt-get install -y "${APT_PACKAGES[@]}"
}

function provisioning_install_python() {
    echo "Устанавливаем Python 3.10 и необходимые пакеты..."
    apt-get update
    apt-get install -y software-properties-common
    add-apt-repository ppa:deadsnakes/ppa -y
    apt-get update
    apt-get install -y python3.10 python3.10-venv
}

# =========================================
# Клонирование Forge
# =========================================
function provisioning_clone_forge() {
    if [[ ! -d "${FORGE_DIR}" ]]; then
        echo "Клонируем Forge..."
        git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git "${FORGE_DIR}"
    else
        echo "Forge уже установлен. Пропускаем клонирование."
    fi
}

# =========================================
# Создание виртуального окружения
# =========================================
function provisioning_setup_python_venv() {
    if [[ ! -d "${UBUNTU_HOME}/venv" ]]; then
        echo "Создаём виртуальное окружение Python 3.10..."
        python3.10 -m venv "${UBUNTU_HOME}/venv"
    else
        echo "Виртуальное окружение уже существует. Пропускаем."
    fi
}

# =========================================
# Установка Extensions
# =========================================
function provisioning_get_extensions() {
    mkdir -p "${FORGE_DIR}/extensions"
    for repo in "${EXTENSIONS[@]}"; do
        dir="${repo##*/}"
        path="${FORGE_DIR}/extensions/${dir}"
        if [[ ! -d $path ]]; then
            echo "Скачиваем расширение: ${repo}"
            git clone "${repo}" "${path}" --recursive
        else
            echo "Расширение ${dir} уже установлено. Пропускаем."
        fi
    done
}

# =========================================
# Загрузка моделей и конфигов
# =========================================
function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    for url in "$@"; do
        filename=$(basename "$url")
        if [[ ! -f "${dir}/${filename}" ]]; then
            echo "Скачиваем: $filename"
            wget -qnc --content-disposition --show-progress -P "$dir" "$url"
        else
            echo "Файл $filename уже существует. Пропускаем."
        fi
    done
}

# =========================================
# Настройка supervisor
# =========================================
function provisioning_setup_supervisor() {
    echo "Настраиваем Supervisor для Forge..."

    cat > "$SUPERVISOR_CONF" <<EOL
[program:forge]
directory=${FORGE_DIR}
command=/usr/bin/env bash ${FORGE_DIR}/webui.sh --api --disable-safe-unpickle --enable-insecure-extension-access --no-download-sd-model --no-half-vae --disable-console-progressbars --cuda-malloc --api-auth ${FORGE_AUTH_USER}:${FORGE_AUTH_PASS} --gradio-auth ${FORGE_AUTH_USER}:${FORGE_AUTH_PASS} --listen
autostart=true
autorestart=true
startsecs=10
startretries=3
stdout_logfile=${LOG_DIR}/forge.log
stderr_logfile=${LOG_DIR}/forge.err
stopsignal=TERM
user=root
EOL
}

# =========================================
# Перезапуск supervisor
# =========================================
function provisioning_restart_supervisor() {
    echo "Перезапускаем Supervisor..."
    supervisorctl reread
    supervisorctl update
    supervisorctl start forge
}

# =========================================
# Вспомогательные функции
# =========================================
function provisioning_print_header() {
    echo "##############################################"
    echo "# Provisioning Forge container..."
    echo "##############################################"
}

function provisioning_print_end() {
    echo "##############################################"
    echo "# Forge setup complete! Service managed by supervisor."
    echo "# Logs: ${LOG_DIR}/forge.log and ${LOG_DIR}/forge.err"
    echo "##############################################"
}

# =========================================
# Запуск provisioning
# =========================================
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
