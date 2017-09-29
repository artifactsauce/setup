#!/usr/bin/env bash

# perl -MPath::Class -I$(dirname $SOURCE_FILE) -nl -e '$_ !~/^\. ((\$\(dirname \$0\))?(.+))/ ? print $_ : $2 ? print file($INC[0].$3)->slurp : print file($3)->slurp' $SOURCE_FILE > $TARGET_FILE

set -eu

. $(dirname $0)/../../lib/bash/functions
. $(dirname $0)/../../lib/bash/logger

: ${PROGLETS_REPOSITORY_HOME:="git@github.com:artifactsauce"}
: ${PROGLETS_DEPLOY_DIRECTORY:="$HOME/src/github.com/artifactsauce"}

_create.required.directories() {
    local errflag=0
    while read
    do
        local dir_path="$REPLY"
        if [ ! -d $dir_path ] && ! mkdir -p $dir_path; then
            echo "$(date) [WARN] directory could not be created: '${dir_path}'" >&2
            errflag=1
        fi
    done <<EOF
$HOME/bin
$HOME/pkg
$HOME/src
$HOME/src/github.com
$PROGLETS_DEPLOY_DIRECTORY
EOF
    if [ $errflag -eq 1 ]; then
        echo "$(date) [ERROR] required directories could be created not all" >&2
        exit 1
    fi
}

_clone.initial_repository() {
    local repository_name="proglets"
    if [ -d "${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/.git" ]; then
        echo "$(date) [WARN] Already exists: ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/.git" >&2
    else
        git clone $PROGLETS_REPOSITORY_HOME/${repository_name}.git ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}
        echo <<EOF >&2
Notice:
  Write down into \`.bash_profile\` or \`.zshrc\`.

  PATH=${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/bin:\$PATH
EOF
    fi

    PATH=${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/bin:$PATH
}

_clone.dotfile_repository() {
    local repository_name="dotfiles"
    if [ -d "${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/.git" ]; then
        echo "$(date) [WARN] Already exists: ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/.git" >&2
    else
        git clone $PROGLETS_REPOSITORY_HOME/${repository_name}.git ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}

        cd ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}
        git submodule init && git submodule update --init --recursive

        ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/bin/init

        cd ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/zprezto
        git pull && git submodule update --init --recursive

        zsh ${PROGLETS_DEPLOY_DIRECTORY}/${repository_name}/bin/prezto.init
    fi
}

_prepare.Darwin() {
    [ $(uname -s) = "Darwin" ] || return 0

    if xcodebuild -checkFirstLaunchStatus > /dev/null; then
        xcode-select --install || test 0
        sudo xcodebuild -license
    fi

    if [[ -d /usr/local ]]; then
        sudo chown -R $(whoami):admin /usr/local
    else
        sudo mkdir /usr/local && sudo chflags norestricted /usr/local && sudo chown -R $(whoami):admin /usr/local
    fi

    if [ ! -d /usr/local/.git ]; then
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    mpkg install brew
}

_prepare.Linux() {
    [ $(uname -s) = "Linux" ] || return 0
    sudo mpkg install apt
}

_install.elisp() {
    if ! which python > /dev/null || ! which emacs > /dev/null; then
        return 0
    fi

    if [ $(uname -s) = "Linux" ] && ! which cask > /dev/null; then
        curl -fsSkL https://raw.github.com/cask/cask/master/go | python
    fi
    cd ${PROGLETS_DEPLOY_DIRECTORY}/dotfiles/emacs.d
    cask install
}

_install.ruby() {
    which rbenv > /dev/null || return 0
    eval "$(rbenv init -)"
    local install_version
    install_version=$(rbenv install --list | perl -nl -e '/^\s*([\.\d]+)$/ and $x = $1; END { print $x }')
    rbenv versions | grep "${install_version}" && return 0
    rbenv install $install_version
    rbenv global $install_version
    mpkg install gem
}

_install.python() {
    which pyenv > /dev/null || return 0
    eval "$(pyenv init -)"
    local install_version
    install_version=$(pyenv install --list | perl -nl -e '/^\s*([\.\d]+)$/ and $x = $1; END { print $x }')
    pyenv versions | grep "${install_version}" && return 0
    pyenv install $install_version
    pyenv global $install_version
    mpkg install pip
}

_install.perl() {
    which plenv > /dev/null || return 0
    eval "$(plenv init -)"
    local install_version
    install_version=$(plenv install --list | perl -nl -e '/^\s*(\d+)\.(\d+)\.(\d+)$/ || next; $2 % 2 == 1 && next; $x = "$1.$2.$3"; END { print $x }')
    plenv versions | grep "${install_version}" && return 0
    plenv install $install_version
    plenv global $install_version
    plenv install-cpanm
    cpanm Menlo
    plenv rehash
    mpkg install cpan
}

_install.node() {
    which nvm > /dev/null || return 0
    NVM_DIR="$HOME/.nvm"
    . "$(realpath $(brew --prefix nvm))/nvm.sh"
    local install_version
    install_version=$(nvm ls-remote | perl -nl -e '/v(\d+\.\d+\.\d+)/ || next; $x = $1; END { print $x }')
    nvm ls | grep "${install_version}" && return 0
    nvm install "v${install_version}"
    nvm use default
    mpkg install npm
}

_create.required.directories
_clone.initial_repository
_clone.dotfile_repository

if ! which proglets > /dev/null; then
    echo "$(date) [ERROR] 'proglets' command could not found."
    exit 1
fi

_prepare.Darwin
_prepare.Linux

#_install.elisp
_install.ruby
_install.python
_install.perl
_install.node


echo "$(date) [INFO] Finished"
exit 0
