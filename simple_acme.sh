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
options=("cloudflare" "aliyun")

# 支持的CA服务
ca_server=("letsencrypt" "zerossl")

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

update_script() {
    REMOTE_URL="https://ghp.ci/https://raw.githubusercontent.com/boloc/simple_acme/main/simple_acme.sh"

    # 下载远程文件到临时文件
    TEMP_FILE=$(mktemp)
    curl -s -o "$TEMP_FILE" "$REMOTE_URL"

    # 检查临时文件是否非空
    if [[ -s "$TEMP_FILE" ]]; then
        if ! diff -q "$0" "$TEMP_FILE" > /dev/null; then
            echo $(info_msg "检测到脚本更新,正在更新新版本...")
            # 将下载的内容移动到新的文件中
            NEW_FILE="${0}.new"
            mv "$TEMP_FILE" "$NEW_FILE"
            # 赋予执行权限
            chmod +x "$NEW_FILE"
            # 替换当前脚本
            mv "$NEW_FILE" "$0"
            echo $(info_msg "更新完成")
            # 重新执行更新后的脚本
            source "$0"
        else
            # 没有检测到更新，删除临时文件
            rm "$TEMP_FILE"
        fi
    else
        echo $(warning_msg "下载出错,保留旧版本继续执行")
        rm "$TEMP_FILE"
    fi
}

pre_check() {
    OS=$(cat /etc/os-release | grep -o -E "Debian|Ubuntu|CentOS" | head -n 1)
    if [[ $OS == "Debian" || $OS == "Ubuntu" || $OS == "CentOS" ]]; then
        echo $(warning_msg "检测到你的系统是${OS}")
    else
        echo $(error_msg "很抱歉,你的系统暂不受支持")
        exit 1
    fi

    # 临时创建一个目录以检查是否有写权限
    if ! (mkdir -p "/home/temp_test_dir" 2>/dev/null && rmdir "/home/temp_test_dir"); then
        echo "当前脚本未有写权限,请尝试以root权限执行此脚本"
        exit 1
    fi

    # 根据不同的发行版安装 socat
    case "$OS" in
    "Ubuntu" | "Debian")
        if ! command -v socat &>/dev/null; then
            # echo "socat未安装，正在安装..."
            sudo apt update
            sudo apt install -y socat
        fi
        ;;
    "CentOS")
        if ! command -v socat &>/dev/null; then
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
        # echo $(warning_msg "检查到acme.sh已经存在,跳过本此安装。")
        echo $(warning_msg "检测到acme.sh已经存在...")
        cd $acme_dir
        ./acme.sh --upgrade --auto-upgrade
    else
        echo $(warning_msg "acme.sh不存在,将进行安装...")
        # 执行 acme.sh 安装脚本
        wget -qO- https://ghp.ci/https://raw.githubusercontent.com/boloc/simple_acme/main/get.acme.sh | bash
        # git clone --depth 1 https://github.com/acmesh-official/acme.sh.git .acme.sh

        # 检查安装是否成功
        if [ $? -ne 0 ]; then
            echo "安装失败：可能是由于权限或者网络问题。请尝试重新运行脚本。"
            exit 1
        fi
        # 重新寻找acme目录
        acme_dir=$(find / -type d -name ".acme.sh" 2>/dev/null)
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
apply_type=''
choose_api_type() {
    # 默认选项 cloudflare
    default_choice=${options[0]}

    echo "请选择调用的api申请方式:"
    # 使用循环动态输出选项
    for i in "${!options[@]}"; do
        echo "$((i + 1))) ${options[$i]}"
    done

    # 读取用户输入
    read -p "请输入选项编号 (回车默认: $default_choice): " choice

    case $choice in
    [1-2])
        apply_type="${options[$((choice - 1))]}"
        echo $(info_msg "当前选择: $apply_type")
        ;;
    "")
        # 如果用户按回车
        apply_type=$default_choice
        echo $(info_msg "当前选择: $apply_type")
        ;;
    *)
        # 如果输入了无效的值
        echo $(error_msg "输入有误，已选择默认: $default_choice")
        apply_type=$default_choice
        ;;
    esac
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

# 配置Aliyun局部令牌
aliyun_action() {
    # 获取 AccessKey ID
    Ali_Key=$(get_non_empty_input "请输入 AccessKey ID 的值")
    # 获取 AccessKey Secret
    Ali_Secret=$(get_non_empty_input "请输入 AccessKey Secret 的值")

    # 导出环境变量
    export Ali_Key
    export Ali_Secret

    echo $(info_msg "已成功设置环境变量：")
    echo "Ali_Key: $Ali_Key"
    echo "Ali_Secret: $Ali_Secret"
}

apply_by_type() {
    case $apply_type in
    "cloudflare")
        cloudflare_action
        ;;
    "aliyun")
        aliyun_action
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

# 配置ZeroSSL配置
zerossl_action() {
    # 获取 EAB KID
    EAB_KID=$(get_non_empty_input "请输入从ZeroSSL中获取到的 EAB KID 的值")
    # 获取 EAB HMAC Key
    EAB_HMAC_KEY=$(get_non_empty_input "请输入从ZeroSSL中获取到的 EAB HMAC KEY 的值")

    # 导出环境变量
    export EAB_KID
    export EAB_HMAC_KEY

    echo $(info_msg "已成功设置环境变量：")
    echo "EAB_KID: $EAB_KID"
    echo "EAB_HMAC_KEY: $EAB_HMAC_KEY"
}

# 选择CA机构服务
ApplyServer=''
choose_ca_server() {
    # 默认选项 letsencrypt
    default_choice=${ca_server[0]}

    echo "请选择调用的 CA 方式:"
    # 使用循环动态输出选项
    for i in "${!ca_server[@]}"; do
        echo "$((i + 1))) ${ca_server[$i]}"
    done

    # 读取用户输入
    read -p "请输入选项编号 (回车默认: $default_choice): " choice

    case $choice in
    [1-2])
        server="${ca_server[$((choice - 1))]}"
        echo $(info_msg "当前选择: $server")
        ;;
    "")
        # 如果用户按回车
        server=$default_choice
        echo $(info_msg "当前选择: $server")
        ;;
    *)
        # 如果输入了无效的值
        echo $(error_msg "输入有误，已选择默认: $default_choice")
        server=$default_choice
        ;;
    esac

    # 执行zerossl需要的额外操作
    if [ $server = 'zerossl' ]; then
        zerossl_action
    fi
    ApplyServer=$server
}

build_acme() {
    echo $(info_msg "执行签发证书......")

    cd $acme_dir
    # 切换默认证书签发的CA机构
    ./acme.sh --set-default-ca --server $ApplyServer
    # echo "./acme.sh --set-default-ca --server zerossl

    # ZeroSSL需要配置相关参数
    if [ $ApplyServer = 'zerossl' ]; then
        ./acme.sh --register-account --server zerossl --eab-kid $EAB_KID --eab-hmac-key $EAB_HMAC_KEY
        # echo "./acme.sh  --register-account  --server zerossl  --eab-kid $EAB_KID  --eab-hmac-key  $EAB_HMAC_KEY"
    fi

    # 构建命令
    acme_command="./acme.sh"
    for domain in "${domains_array[@]}"; do
        acme_command+=" -d $domain"
    done

    # DNS 验证类型
    dnsType='dns_cf'
    if [ $apply_type = 'aliyun' ]; then
        dnsType='dns_ali'
    fi

    acme_command+=" --issue --dns $dnsType -k ec-256  --log --dnssleep 30 "

    # 执行命令
    eval "$acme_command"

    # 安装证书到指定位置(至此SSL证书步骤配置结束)
    installcert_command="./acme.sh --installcert --ecc"
    filename='certificate'
    for domain in "${domains_array[@]}"; do
        installcert_command+=" -d $domain"
        # 避免*成为文件名
        if [[ "$domain" == \*.?* ]]; then
            # Extract the main domain from wildcard domain
            main_domain="${domain#*.}"
            if [ "$filename" = "certificate" ]; then
                filename="$main_domain"
            fi
        else
            if [ "$filename" = "certificate" ]; then
                filename="$domain"
            fi
        fi
    done
    installcert_command+=" --fullchain-file $ssl_dir/$filename.crt --key-file $ssl_dir/$filename.key"
    # echo $installcert_command
    eval "$installcert_command"
}

# 更新脚本
update_script
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
# 选择CA机构服务
choose_ca_server
# 构建acme执行
build_acme
exit 0
