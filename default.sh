#!/bin/bash

FORGE_DIR=${WORKSPACE}/stable-diffusion-webui-forge

APT_PACKAGES=(
    git
    wget
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

### ============ DO NOT EDIT BELOW THIS LINE ============

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_extensions
    provisioning_get_files "${FORGE_DIR}/models/Stable-diffusion" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${FORGE_DIR}/models/ESRGAN" "${ESRGAN_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        apt-get update
        apt-get install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_extensions() {
    mkdir -p "${FORGE_DIR}/extensions"
    for repo in "${EXTENSIONS[@]}"; do
        dir="${repo##*/}"
        path="${FORGE_DIR}/extensions/${dir}"
        if [[ ! -d $path ]]; then
            printf "Downloading extension: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    for url in "$@"; do
        printf "Downloading: %s\n" "$url"
        wget -qnc --content-disposition --show-progress -P "$dir" "$url"
    done
}

function provisioning_print_header() {
    echo "##############################################"
    echo "# Provisioning Forge container..."
    echo "##############################################"
}

function provisioning_print_end() {
    echo "Provisioning complete! Forge will start now."
}

# Run provisioning unless disabled
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
