#!/usr/bin/env bash

set -e

CONTAINER_OS=${1:-"alpine"}
USERNAME=${2:-"automatic"}
SOURCE_SOCKET=${3:-"/var/run/docker-host.sock"}
TARGET_SOCKET=${4:-"/var/run/docker.sock"}

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

function apt_get_update_if_needed() {
  if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" -eq 0 ]; then
    apt-get update
  fi
}

function check_packages() {
  if [ "${CONTAINER_OS}" = "debian" ]; then
    if ! dpkg --status "$@" >/dev/null 2>&1; then
      apt_get_update_if_needed
      apt-get install --no-install-recommends --assume-yes "$@"
    fi
  elif [ "${CONTAINER_OS}" = "alpine" ]; then
    if ! apk info --installed "$@" >/dev/null 2>&1; then
      apk update
      apk add --no-cache --latest "$@"
    fi
  fi
}

if [ "${CONTAINER_OS}" = "debian" ]; then
  export DEBIAN_FRONTEND=noninteractive
  check_packages \
    acl \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    lsb-release

  # shellcheck source=/dev/null
  source /etc/os-release

  curl -fsSL https://download.docker.com/linux/${ID}/gpg | gpg --dearmor >/usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" >/etc/apt/sources.list.d/docker.list

  apt-get update
elif [ "${CONTAINER_OS}" = "alpine" ]; then
  check_packages \
    acl
fi

if type docker >/dev/null 2>&1; then
  echo "Docker is already installed."
else
  if [ "${CONTAINER_OS}" = "debian" ]; then
    check_packages \
      docker-ce-cli
  elif [ "${CONTAINER_OS}" = "alpine" ]; then
    check_packages \
      docker
    if [ -e "/bin/bash" ]; then
      apk add --no-cache --latest \
        docker-bash-completion
    fi
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
