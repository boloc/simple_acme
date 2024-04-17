#!/bin/bash

################################################################
# Simple acme
# @author bub12310@outlook.com boloc
# 使用acme.sh申请SSL
################################################################

Red_font_prefix="\033[31m"
Green_font_prefix="\033[32m"
Yellow_font_prefix="\033[33m"
Font_color_suffix="\033[0m"

# acme存在目录
acme_dir=''
# 选择api方式,目前仅支持cloudflare
options=("cloudflare")

info_msg() {
    echo -e "${Green_font_prefix}$1${Font_color_suffix}"
    return 0
}

warning_msg() {
    echo -e "${Yellow_font_prefix}$1${Font_color_suffix}"
    return 0
}

error_msg() {
    echo -e "${Red_font_prefix}$1${Font_color_suffix}"
    return 0
}

pre_check() {
    OS=$(cat /etc/os-release | grep -o -E "Debian|Ubuntu|CentOS" | head -n 1)
    if [[ $OS == "Debian" || $OS == "Ubuntu" || $OS == "CentOS" ]]; then
        echo $(warning_msg "检测到你的系统是${OS}")
    else
        echo $(error_msg "很抱歉,你的系统暂不受支持")
        exit 1
    fi

    # 根据不同的发行版安装 socat
    case "$OS" in
    "Ubuntu" | "Debian")
        if ! command -v socat &> /dev/null; then
            # echo "socat未安装，正在安装..."
            sudo apt update
            sudo apt install -y socat
        fi
        ;;
    "CentOS")
        if ! command -v socat &> /dev/null; then
            # echo "socat未安装，正在安装..."
            sudo yum update -y
            sudo yum install -y socat
        fi
        ;;
    *)
        echo "很抱歉，你的系统暂不受支持"
        exit 1
        ;;
    esac
}

install_acme() {
    acme_dir=$(find / -type d -name ".acme.sh" 2>/dev/null)
    if [ -n "$acme_dir" ]; then
        echo $(warning_msg "检查到acme.sh已经存在,跳过本此安装。")
    else
        echo $(warning_msg "acme.sh不存在,将进行安装...")
        # 执行 acme.sh 安装脚本
        wget -qO- https://get.acme.sh | bash
        # 检查安装是否成功
        if [ $? -ne 0 ]; then
            echo "安装失败：可能是由于权限问题。请尝试以管理员权限或适当的权限重新运行脚本。"
            exit 1
        fi
    fi
}

# 定义函数来获取非空值
get_non_empty_input() {
    local prompt="$1"
    local input
    while true; do
        read -p "$prompt: " input
        if [[ -n "$input" ]]; then
            echo "$input"
            break
        else
            printf "${Red_font_prefix}输入有误,请重试${Font_color_suffix} \n" >&2 # 将输出发送到 stderr
        fi
    done
}

# 定义选项列表
apply_type=""
choose_api_type() {
    while true; do
        echo "请选择调用的api申请方式(回车默认:cloudflare):"
        for option in "${options[@]}"; do
            echo "$option" # 列出循环值
        done
        read choice

        case $choice in
        "")
            echo $(info_msg "已选中:cloudfalre")
            apply_type='cloudflare'
            break
            ;;
        "cloudfalre")
            echo $(info_msg "已选中:$choice")
            apply_type=$choice
            break
            ;;
        *)
            echo $(error_msg "输入有误，请重试")
            ;;
        esac
    done
}

# 配置Cloudflare局部令牌
cloudflare_action() {
    # 获取 CF_Token
    CF_Token=$(get_non_empty_input "请输入 CF_Token 的值")
    # 获取 CF_Account_ID
    CF_Account_ID=$(get_non_empty_input "请输入 CF_Account_ID 的值")
    # 获取 CF_Zone_ID
    CF_Zone_ID=$(get_non_empty_input "请输入 CF_Zone_ID 的值")

    # 导出环境变量
    export CF_Token
    export CF_Account_ID
    export CF_Zone_ID

    echo $(info_msg "已成功设置环境变量：")
    echo "CF_Token: $CF_Token"
    echo "CF_Account_ID: $CF_Account_ID"
    echo "CF_Zone_ID: $CF_Zone_ID"
}

apply_by_type() {
    case $apply_type in
    "cloudflare")
        cloudflare_action
        ;;
    esac
}

pending_domains() {
    while true; do
        read -p "请输入你申请证书的域名 (多个域名以空格隔开 例:example.com *.example.com): " domain_names
        if [ -z "$domain_names" ]; then
            echo $(error_msg "域名不能为空，请提供至少一个域名。")
            continue
        fi

        # 验证输入的域名格式
        valid_domain_regex="^(\*\.){0,1}([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.){1,}[a-zA-Z]{2,}$"
        IFS=' ' read -ra domains_array <<<"$domain_names"

        # 单独验证每个输入的域名格式
        valid_format=true
        for domain in "${domains_array[@]}"; do
            if ! [[ $domain =~ $valid_domain_regex ]]; then
                echo $(error_msg "${domain} 的域名格式无效。请提供有效的域名。")
                valid_format=false
                break
            fi
        done

        if [ "$valid_format" = false ]; then
            continue
        fi

        # 输入都合法，退出循环
        break
    done

    while true; do
        read -p "请输入证书存放目录 (绝对路径 例:/ssl): " ssl_dir
        if [ -z "$ssl_dir" ]; then
            echo $(error_msg "请指定证书存在目录。")
            continue
        fi

        if [ ! -d "$ssl_dir" ]; then # 不存在目录,自动创建
            mkdir -p "$ssl_dir"
            echo $(warning_msg "证书目录不存在，将自动创建存放目录：$ssl_dir")
        fi

        # 输入都合法，退出循环
        break
    done
}

build_acme() {
    cd $acme_dir
    # 切换默认证书签发的CA机构
    ./acme.sh --set-default-ca --server letsencrypt

    # 构建命令
    acme_command="./acme.sh"
    for domain in "${domains_array[@]}"; do
        acme_command+=" -d $domain"
    done
    acme_command+=" --issue --dns dns_cf -k ec-256  --log --dnssleep 30 "
    # echo $acme_command
    # 执行命令
    eval "$acme_command"

    # 安装证书到指定位置(至此SSL证书步骤配置结束)
    installcert_command="./acme.sh --installcert --ecc"
    filename='certificate'
    for domain in "${domains_array[@]}"; do
        installcert_command+=" -d $domain"
        if [ "$filename" = "certificate" ]; then
            filename="$domain"
        fi
    done
    installcert_command+=" --fullchain-file $ssl_dir/$filename.crt --key-file $ssl_dir/$filename.key"
    # echo $installcert_command
    eval "$installcert_command"
}

# 系统检测 && 前置准备
pre_check
# 安装acme
install_acme
# 选择api类型
choose_api_type
# 根据选定api类型执行申请
apply_by_type
# 域名填写
pending_domains
# 构建acme执行
build_acme

exit 0
