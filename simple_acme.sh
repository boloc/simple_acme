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
    REMOTE_URL="https://raw.githubusercontent.com/boloc/simple_acme/main/simple_acme.sh"

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
    echo $(info_msg "开始系统环境检查...")

    # 检查操作系统
    OS=$(cat /etc/os-release | grep -o -E "Debian|Ubuntu|CentOS" | head -n 1)
    if [[ $OS == "Debian" || $OS == "Ubuntu" || $OS == "CentOS" ]]; then
        echo $(info_msg "✓ 操作系统: $OS")
    else
        echo $(error_msg "✗ 不支持的操作系统，仅支持 Debian/Ubuntu/CentOS")
        exit 1
    fi

    # 检查用户权限
    USER_HOME=$(eval echo ~$(whoami))
    if ! (mkdir -p "$USER_HOME/temp_test_dir" 2>/dev/null && rmdir "$USER_HOME/temp_test_dir"); then
        echo $(error_msg "✗ 当前用户没有写权限，请检查权限设置")
        exit 1
    fi
    echo $(info_msg "✓ 用户权限: $(whoami)")

    # 检查系统依赖软件
    echo $(info_msg "检查必需软件...")
    local required_tools=("curl" "openssl" "cron" "socat")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    # 如果有缺失的工具，自动安装
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo $(warning_msg "缺少依赖: ${missing_tools[*]}，正在安装...")

        case "$OS" in
        "Ubuntu" | "Debian")
            local apt_packages=""
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "cron") apt_packages+=" cron" ;;
                    "curl") apt_packages+=" curl" ;;
                    "openssl") apt_packages+=" openssl" ;;
                    "socat") apt_packages+=" socat" ;;
                esac
            done

            if [ -n "$apt_packages" ]; then
                apt update && apt install -y $apt_packages
            fi
            ;;

        "CentOS")
            local yum_packages=""
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "cron") yum_packages+=" cronie" ;;
                    "curl") yum_packages+=" curl" ;;
                    "openssl") yum_packages+=" openssl" ;;
                    "socat") yum_packages+=" socat" ;;
                esac
            done

            if [ -n "$yum_packages" ]; then
                yum update -y && yum install -y $yum_packages
            fi
            ;;
        esac

        # 验证安装结果
        local still_missing=()
        for tool in "${missing_tools[@]}"; do
            if ! command -v "$tool" &>/dev/null; then
                still_missing+=("$tool")
            fi
        done

        if [ ${#still_missing[@]} -gt 0 ]; then
            echo $(error_msg "✗ 以下软件安装失败: ${still_missing[*]}")
            echo $(error_msg "请手动安装后重新运行脚本")
            exit 1
        fi
    fi
    echo $(info_msg "✓ 必需软件: curl, openssl, cron, socat")

    echo $(info_msg "========================================")
    echo $(info_msg "系统环境检查完成！")
    echo $(info_msg "✓ 系统: $OS")
    echo $(info_msg "✓ 用户: $(whoami)")
    echo $(info_msg "✓ 依赖: 已安装")
    echo $(info_msg "========================================")
}

install_acme() {
    # 获取当前用户信息
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)

    # 检查 acme.sh 是否已经在 PATH 中可用
    if command -v acme.sh &>/dev/null; then
        echo $(info_msg "检测到 acme.sh 已安装并可直接使用")
        acme.sh --upgrade --auto-upgrade
        return 0
    fi

    # 设置用户相关的路径
    ACME_HOME="$USER_HOME/.acme.sh"
    SHELL_RC="$USER_HOME/.bashrc"

    # 如果是 zsh，使用 .zshrc
    if [ "$SHELL" = "/usr/bin/zsh" ] || [ "$SHELL" = "/bin/zsh" ]; then
        SHELL_RC="$USER_HOME/.zshrc"
    fi

    echo $(info_msg "当前用户: $CURRENT_USER")
    echo $(info_msg "用户主目录: $USER_HOME")
    echo $(info_msg "Shell 配置文件: $SHELL_RC")

    # 检查用户目录下是否存在 .acme.sh
    if [ -d "$ACME_HOME" ]; then
        echo $(warning_msg "检测到 acme.sh 已存在于 $ACME_HOME...")
        cd "$ACME_HOME"
        ./acme.sh --upgrade --auto-upgrade

        # 添加到 PATH
        if ! grep -q "$ACME_HOME" "$SHELL_RC" 2>/dev/null; then
            echo "export PATH=\"$ACME_HOME:\$PATH\"" >> "$SHELL_RC"
            echo $(info_msg "已将 acme.sh 添加到 $SHELL_RC")
        fi

        # 如果是 root 用户，创建软链接到 /usr/local/bin
        if [ "$CURRENT_USER" = "root" ] && [ ! -f "/usr/local/bin/acme.sh" ]; then
            ln -sf "$ACME_HOME/acme.sh" /usr/local/bin/acme.sh
            echo $(info_msg "已创建 acme.sh 软链接到 /usr/local/bin")
        fi

        # 如果是普通用户，创建软链接到用户的 bin 目录
        if [ "$CURRENT_USER" != "root" ]; then
            mkdir -p "$USER_HOME/.local/bin"
            if [ ! -f "$USER_HOME/.local/bin/acme.sh" ]; then
                ln -sf "$ACME_HOME/acme.sh" "$USER_HOME/.local/bin/acme.sh"
                echo $(info_msg "已创建 acme.sh 软链接到 $USER_HOME/.local/bin")
            fi

            # 添加 ~/.local/bin 到 PATH
            if ! grep -q "$USER_HOME/.local/bin" "$SHELL_RC" 2>/dev/null; then
                echo "export PATH=\"$USER_HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
                echo $(info_msg "已将 ~/.local/bin 添加到 PATH")
            fi
        fi
    else
        echo $(warning_msg "acme.sh 不存在，将安装到 $ACME_HOME...")

        # 安装到用户目录
        cd "$USER_HOME"
        curl https://get.acme.sh | sh -s email=my@example.com

        # 检查安装是否成功
        if [ $? -ne 0 ]; then
            echo $(error_msg "安装失败：可能是由于权限或者网络问题。请尝试重新运行脚本。")
            exit 1
        fi

        # 添加到 PATH
        if ! grep -q "$ACME_HOME" "$SHELL_RC" 2>/dev/null; then
            echo "export PATH=\"$ACME_HOME:\$PATH\"" >> "$SHELL_RC"
            echo $(info_msg "已将 acme.sh 添加到 $SHELL_RC")
        fi

        # 如果是 root 用户，创建软链接到 /usr/local/bin
        if [ "$CURRENT_USER" = "root" ]; then
            ln -sf "$ACME_HOME/acme.sh" /usr/local/bin/acme.sh
            echo $(info_msg "已创建 acme.sh 软链接到 /usr/local/bin")
        else
            # 如果是普通用户，创建软链接到用户的 bin 目录
            mkdir -p "$USER_HOME/.local/bin"
            ln -sf "$ACME_HOME/acme.sh" "$USER_HOME/.local/bin/acme.sh"
            echo $(info_msg "已创建 acme.sh 软链接到 $USER_HOME/.local/bin")

            # 添加 ~/.local/bin 到 PATH
            if ! grep -q "$USER_HOME/.local/bin" "$SHELL_RC" 2>/dev/null; then
                echo "export PATH=\"$USER_HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
                echo $(info_msg "已将 ~/.local/bin 添加到 PATH")
            fi
        fi

        echo $(info_msg "acme.sh 安装完成！请运行 'source $SHELL_RC' 或重新登录以使 PATH 生效")
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
    echo $(info_msg "ZeroSSL 配置选项：")
    echo "1) 使用 EAB 凭据（可在 ZeroSSL 控制台管理证书）"
    echo "2) 不使用 EAB 凭据（仅申请证书，无法在控制台管理）"

    read -p "请选择 (1/2，默认为2): " eab_choice

    case $eab_choice in
    1)
        echo $(info_msg "请从 ZeroSSL 开发者页面获取 EAB 凭据")
        # 获取 EAB KID
        EAB_KID=$(get_non_empty_input "请输入 EAB KID")
        # 获取 EAB HMAC Key
        EAB_HMAC_KEY=$(get_non_empty_input "请输入 EAB HMAC KEY")

        # 导出环境变量
        export EAB_KID
        export EAB_HMAC_KEY
        USE_EAB=true

        echo $(info_msg "已设置 EAB 凭据，证书将关联到您的 ZeroSSL 账户")
        ;;
    2|"")
        echo $(info_msg "将不使用 EAB 凭据，直接申请证书")
        USE_EAB=false
        ;;
    *)
        echo $(warning_msg "无效选择，将不使用 EAB 凭据")
        USE_EAB=false
        ;;
    esac
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

    # 切换默认证书签发的CA机构
    acme.sh --set-default-ca --server $ApplyServer

    # ZeroSSL需要配置相关参数
    if [ $ApplyServer = 'zerossl' ]; then
        if [ "$USE_EAB" = "true" ]; then
            echo $(info_msg "使用 EAB 凭据注册 ZeroSSL 账户...")
            acme.sh --register-account --server zerossl --eab-kid $EAB_KID --eab-hmac-key $EAB_HMAC_KEY
        else
            echo $(info_msg "使用 ZeroSSL 申请证书（无 EAB 凭据）...")
            # 不需要特殊的账户注册，acme.sh 会自动处理
        fi
    fi

    # 构建命令
    acme_command="acme.sh"
    for domain in "${domains_array[@]}"; do
        acme_command+=" -d $domain"
    done

    # DNS 验证类型
    dnsType='dns_cf'
    if [ $apply_type = 'aliyun' ]; then
        dnsType='dns_ali'
    fi

    acme_command+=" --issue --dns $dnsType -k ec-256  --log  "

    # 执行命令
    eval "$acme_command"

    # 安装证书到指定位置(至此SSL证书步骤配置结束)
    installcert_command="acme.sh --install-cert --ecc"
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

    # 定义证书文件路径变量
    cert_base_path="$ssl_dir/$filename"
    cert_file="$cert_base_path.crt"                    # 域名证书
    ca_file="$cert_base_path-ca.pem"                   # CA证书(中间证书)
    key_file="$cert_base_path.key"                     # 私钥
    fullchain_file="$cert_base_path-fullchain.crt"     # 完整证书链

    # 构建安装证书命令
    installcert_command+=" --cert-file $cert_file"
    installcert_command+=" --ca-file $ca_file"
    installcert_command+=" --key-file $key_file"
    installcert_command+=" --fullchain-file $fullchain_file"

    # 执行安装证书命令
    eval "$installcert_command"

    # 显示生成的证书文件信息
    echo $(info_msg "========================================")
    echo $(info_msg "证书申请完成！生成的文件如下：")
    echo $(info_msg "域名证书: $cert_file")
    echo $(info_msg "CA证书(中间证书): $ca_file")
    echo $(info_msg "私钥文件: $key_file")
    echo $(info_msg "完整证书链: $fullchain_file")
    echo $(info_msg "========================================")
    echo $(warning_msg "使用说明：")
    echo $(warning_msg "• nginx 配置使用: $(basename $fullchain_file) + $(basename $key_file)")
    echo $(warning_msg "• Apache 配置使用: $(basename $fullchain_file) + $(basename $key_file)")
    echo $(warning_msg "• mobileconfig 签名使用: $(basename $cert_file) + $(basename $key_file) + $(basename $ca_file)")
    echo $(info_msg "========================================")
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
