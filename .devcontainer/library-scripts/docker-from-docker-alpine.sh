#!/usr/bin/env bash

USERNAME=${1:-"automatic"}
SOURCE_SOCKET=${2:-"/var/run/docker-host.sock"}
TARGET_SOCKET=${3:-"/var/run/docker.sock"}

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
  exit 1
fi

if [ "${USERNAME}" = "automatic" ]; then
  USERNAME=""
  POSSIBLE_USERS=("codespace" "vscode" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
  for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
    if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
      USERNAME=${CURRENT_USER}
      break
    fi
  done
  if [ "${USERNAME}" = "" ]; then
    USERNAME=root
  fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} >/dev/null 2>&1; then
  USERNAME=root
fi

function check_packages() {
  if ! apk info --installed "$@" >/dev/null 2>&1; then
    apk update
    apk add --no-cache --latest "$@"
  fi
}

check_packages \
  acl

if type docker >/dev/null 2>&1; then
  echo "Docker is already installed."
else
  check_packages \
    docker
  if [ -e "/bin/bash" ]; then
    apk add --no-cache --latest \
      docker-bash-completion
  fi
fi

if [ "${SOURCE_SOCKET}" != "${TARGET_SOCKET}" ]; then
  touch "${SOURCE_SOCKET}"
  ln -s "${SOURCE_SOCKET}" "${TARGET_SOCKET}"
fi

if ! grep -qE '^docker:' /etc/group; then
  groupadd --system docker
elif [ "${USERNAME}" != "root" ]; then
  usermod -aG docker "${USERNAME}"
fi

tee --append /home/${USERNAME}/.bashrc \
  <<EOF

function sudoIf() {
  if [ "\$(id -u)" -ne 0 ]; then
    sudo "\$@"
  else
    "\$@"
  fi
}

if [ -e "${TARGET_SOCKET}" ]; then
  sudoIf setfacl --modify=user:${USERNAME}:rw ${TARGET_SOCKET}
fi
EOF
