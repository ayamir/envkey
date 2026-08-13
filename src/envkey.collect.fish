# envkey.collect.fish — fish 启动时 source：定义 envkey 函数 + 从 Keychain 加载密钥
# 文件位置（由 install.sh 放置）：$HOME/.local/share/envkey/envkey.collect.fish
# 引用：source ~/.config/fish/config.fish 内。不落任何明文密钥。

# 函数体内用绝对路径、变量名加前缀避免与用户变量冲突
set -gx _envkey_list ~/.config/fish/secret-names
set -g _envkey_bin (command -v envkey; or echo ~/.local/bin/envkey)
set -g _envkey_backend (command -v envkey-backend; or echo ~/.local/bin/envkey-backend)

function envkey -d "Manage secrets stored in macOS Keychain"
    set -l bin $_envkey_bin
    set -l backend $_envkey_backend
    switch "$argv[1]"
        case set
            set -l name $argv[2]
            if test -z "$name"
                echo "usage: envkey set NAME [--from-stdin]" >&2
                return 1
            end
            # 透传给真实命令（交互/管道输入），完成后从后端读回注入当前 shell
            $bin set $argv[2..-1]
            or return $status
            set -gx $name ($backend get $name 2>/dev/null)
        case del
            set -l name $argv[2]
            if test -z "$name"
                echo "usage: envkey del NAME" >&2
                return 1
            end
            $bin del "$name"
            set -q $name; and set -e $name
        case list
            $bin list
        case backend
            $bin backend
        case export
            set -l name $argv[2]
            if test -z "$name"
                echo "usage: envkey export NAME" >&2
                return 1
            end
            eval ($bin export "$name")
        case '*'
            echo "usage: envkey set/del/list/export" >&2
    end
end

# 启动时按名单加载已有密钥
if test -f $_envkey_list
    while read -l _envkey_name
        if test -n "$_envkey_name"; and not set -q $_envkey_name
            set -l _val ($_envkey_backend get $_envkey_name 2>/dev/null)
            if test -n "$_val"
                set -gx $_envkey_name $_val
            else
                echo "warning: keychain item '$_envkey_name' not found; run: envkey set $_envkey_name <value>" >&2
            end
        end
    end < $_envkey_list
end
