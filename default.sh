#!/bin/bash

# ==============================
# Конфигурация путей
# ==============================
FORGE_DIR=${WORKSPACE}/stable-diffusion-webui-forge
UBUNTU_HOME="/home/ubuntu"

# ==============================
# Системные пакеты, которые нужно установить
# ==============================
APT_PACKAGES=(
    git
    wget
    software-properties-common
    python3.10-venv
)

# ==============================
# Массив расширений Forge
# ==============================
EXTENSIONS=(
    "https://github.com/zixaphir/Stable-Diffusion-Webui-Civitai-Helper.git"
    "https://github.com/AUTOMATIC1111/stable-diffusion-webui-rembg.git"
    "https://github.com/Coyote-A/ultimate-upscale-for-automatic1111.git"
)

# ==============================
# Основная модель
# ==============================
CHECKPOINT_MODELS=(
    "https://huggingface.co/ZhenyaYang/flux_1_dev_hyper_8steps_nf4/resolve/main/flux_1_dev_hyper_8steps_nf4.safetensors"
)

# ==============================
# Модель Upscaler
# ==============================
ESRGAN_MODELS=(
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
)

# ==============================
# Конфигурационные файлы Forge
# ==============================
CONFIG_FILES=(
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/config.json"
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/styles_integrated.csv"
    "https://raw.githubusercontent.com/cepreusa/forge/refs/heads/main/ui-config.json"
)

# ==============================
# Главная функция
# ==============================
function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_clone_forge
    provisioning_setup_python_venv
    provisioning_get_extensions
    provisioning_get_files "${FORGE_DIR}/models/Stable-diffusion" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${FORGE_DIR}/models/ESRGAN" "${ESRGAN_MODELS[@]}"
    provisioning_get_files "${FORGE_DIR}" "${CONFIG_FILES[@]}"

     # Avoid git errors because we run as root but files are owned by 'user'
    export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
    git config --file $GIT_CONFIG_GLOBAL --add safe.directory '*'

    cd "${FORGE_DIR}"
    LD_PRELOAD=libtcmalloc_minimal.so.4 \
        python launch.py \
            --skip-python-version-check \
            --no-download-sd-model \
            --do-not-download-clip \
            --no-half \
            --port 11404 \
            --exit
    
    provisioning_print_end
}

# ==============================
# Настройка sudo для ubuntu
# ==============================
function provisioning_setup_sudo_for_ubuntu() {
    echo "Настраиваем sudo для пользователя ubuntu..."
    usermod -aG sudo ubuntu
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-ubuntu
    chmod 440 /etc/sudoers.d/90-ubuntu
}

# ==============================
# Установка системных пакетов
# ==============================
function provisioning_get_apt_packages() {
    echo "Обновляем пакеты и устанавливаем зависимости..."
    apt-get update
    apt-get install -y "${APT_PACKAGES[@]}"
}

# ==============================
# Клонирование Forge
# ==============================
function provisioning_clone_forge() {
    if [[ ! -d "${FORGE_DIR}" ]]; then
        echo "Клонируем репозиторий Forge..."
        git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git "${FORGE_DIR}"
    else
        echo "Forge уже установлен, пропускаем клонирование."
    fi
}

# ==============================
# Создание виртуального окружения Python
# ==============================
function provisioning_setup_python_venv() {
    if [[ ! -d "${UBUNTU_HOME}/venv" ]]; then
        echo "Создаём Python виртуальное окружение..."
        sudo -u ubuntu python3.10 -m venv "${UBUNTU_HOME}/venv"
    else
        echo "Виртуальное окружение уже существует, пропускаем."
    fi
}

# ==============================
# Загрузка расширений Forge
# ==============================
function provisioning_get_extensions() {
    mkdir -p "${FORGE_DIR}/extensions"
    for repo in "${EXTENSIONS[@]}"; do
        dir="${repo##*/}"
        path="${FORGE_DIR}/extensions/${dir}"
        if [[ ! -d $path ]]; then
            echo "Скачиваем расширение: ${repo}"
            git clone "${repo}" "${path}" --recursive
        else
            echo "Расширение ${dir} уже установлено, пропускаем."
        fi
    done
}

# ==============================
# Загрузка моделей и конфигов
# ==============================
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
            echo "Файл $filename уже существует, пропускаем."
        fi
    done
}

# ==============================
# Вспомогательные функции
# ==============================
function provisioning_print_header() {
    echo "##############################################"
    echo "# Provisioning Forge container..."
    echo "##############################################"
}

function provisioning_print_end() {
    echo "##############################################"
    echo "# Provisioning complete! Forge will start now."
    echo "##############################################"
}

# ==============================
# Запуск provisioning
# ==============================
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
