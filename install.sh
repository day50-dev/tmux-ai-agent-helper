#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/sidechat
PIP=$(command -v uv || command -v pipx || command -v pip || command -v pip3 )
JQ=$(command -v jq)

pybin=
if [[ -z "$PIP" ]]; then 
    echo "Woops, we need python and either uv, pip or pipx."
    exit 1
fi
if ! command -v unzip > /dev/null; then
    echo "Woops, unzip needs to be installed."
fi

if [[ $PIP =~ /pipx$ ]]; then 
    # really old pipx - apps is used even in the intl tests i did
    if [[ -z "$pybin" ]]; then
        pybin=$(pipx --help | grep apps | awk ' { print $NF } ' | grep \/ | sed 's/\.$//g;')
    fi
elif [[ $PIP =~ /uv$ ]]; then 
    PIPINSTALL="$PIP tool install --force"
    PIPLIST="uv tool list"
    PIPUPGRADE="uv tool upgrade"
else
    PIPINSTALL="$PIP install --user"
    PIPLIST="$PIP list"
    PIPUPGRADE="$PIP upgrade"
    if [[ $(uname) == "Linux" || "$(pip3 --version | grep homebrew | wc -l)" != 0 ]]; then
        PIP="$PIP --break-system-packages "
    fi
fi

if [[ $(uname) == "Linux" ]]; then
    insdir="$HOME/.local/bin"
    sd="$insdir/sd"
else
    insdir="$HOME/Library/bin"
    if [[ -z "$pybin" ]]; then 
      pybin=$(python3 -msite --user-base)"/bin"
    fi
    sd="$pybin/sd"
fi

trap 'echo "Error on line $LINENO"; read -rp "Press enter to exit..."; exit 1' ERR
echo -e "\n  INSTALLING\n"

[[ -d "$insdir" ]] || mkdir -p "$insdir"

touch ~/.tmux.conf
if ! grep -q "bind h run-shell" ~/.tmux.conf; then
cat << ENDL >> ~/.tmux.conf
bind h run-shell "tmux split-window -h '$insdir/sidechat #{pane_id}'"
bind j display-popup -E "$insdir/sc-picker"
ENDL
    if pgrep -u $UID tmux > /dev/null; then
        tmux source-file "$HOME"/.tmux.conf
    fi
fi

for cmd in sc-tp.py sc-tf.json sc-_parse.py sc-add sc-_common sc-picker sidechat; do
    rm -f "$insdir"/$cmd 
    echo "  ✅ $cmd"
    cp -p "$DIR"/$cmd "$insdir"
done

for pkg in mansnip llcat streamdown; do
    echo "  ✅ $pkg"
    if ! $PIPINSTALL $pkg &> /dev/null; then
        if $PIPLIST |& grep $pkg >/dev/null; then
            $PIPUPGRADE $pkg
        fi
    fi
done

if [[ ! -d ~/.fzf ]]; then
    if ! command -v git > /dev/null; then
        echo "**Important**: git is not installed, install fzf manually"
    else
        git clone --quiet --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install --no-update-rc --no-completion --no-key-bindings >& /dev/null
        for i in ~/.fzf/bin/*; do
            cmd=$(basename $i)
            rm -f "$insdir"/$cmd
            ln -s "$i" "$insdir"/$cmd 
        done
        echo "  ✅ fzf"
    fi
fi

[[ -z "$JQ" ]] && msg="**Important**: Please install jq manually" || msg="You're ready to go!"

if [[ "$insdir" != "$pybin" ]]; then
    binpath="$insdir:$pybin"
else
    binpath="$insdir"
fi

if command -v git > /dev/null; then
    if [[ $(uname) == "Darwin" ]]; then
        sed -i "" "s^#@@INJECTPATH^PATH=\$PATH:$binpath^g" "$insdir/sc-_common"
        sed -i "" "s^@@VERSION^$(cd $DIR;git describe)^g" "$insdir/sc-_common"
    else
        sed -i "s/@@VERSION/$(cd $DIR;git describe)/g" "$insdir/sc-_common"
    fi
fi

if ! echo $PATH | grep "$binpath" > /dev/null; then
    if [[ $(uname) == "Linux" ]]; then
        shell=$(getent passwd $(whoami) | awk -F / '{print $NF}')
    else
        shell=$(basename $SHELL)
    fi
    msg="**Important!**"
    if [[ $shell == "bash" ]]; then
        echo "export PATH=\$PATH:$binpath" >> $HOME/.bashrc
        msg="$msg Run \`source ~/.bashrc\`"
    elif [[ $shell == "zsh" ]]; then
        echo "export PATH=\$PATH:$binpath" >> $HOME/.zshrc
        msg="$msg Run \`source ~/.zshrc\`"
    elif [[ $shell == "fish" ]]; then
        config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
        mkdir -p "$config_dir/fish"
        echo "fish_add_path $binpath" >> "$config_dir/fish"/config.fish
        msg="$msg Run \`source ~/.config/fish/config.fish\`"
    else
        msg="$msg Add $binpath to your path"
    fi
    msg="$msg or restart your shell."
fi


{
cat <<ENDL

### **Success**

$msg

Sidechat's TMUX key strokes:

 * **tmux key + h**: Chat window
 * **tmux key + j**: Recent code snippets

ENDL

} | $sd 
