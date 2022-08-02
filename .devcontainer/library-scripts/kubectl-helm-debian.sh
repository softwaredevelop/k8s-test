#!/usr/bin/env bash

set -e

KUBECTL_VERSION=${1:-"latest"}
KUBECTL_SHA256=${2:-"automatic"}
USERNAME=${3:-"automatic"}

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
  if ! dpkg --status "$@" >/dev/null 2>&1; then
    apt_get_update_if_needed
    apt-get install --no-install-recommends --assume-yes "$@"
  fi
}

find_version_from_git_tags() {
  local variable_name=$1
  local requested_version=${!variable_name}
  if [ "${requested_version}" = "none" ]; then return; fi
  local repository=$2
  local prefix=${3:-"tags/v"}
  local separator=${4:-"."}
  local last_part_optional=${5:-"false"}
  if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
    local escaped_separator=${separator//./\\.}
    local last_part
    if [ "${last_part_optional}" = "true" ]; then
      last_part="(${escaped_separator}[0-9]+)?"
    else
      last_part="${escaped_separator}[0-9]+"
    fi
    local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
    local version_list
    version_list="$(git ls-remote --tags ${repository} | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
    if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
      declare -g ${variable_name}="$(echo "${version_list}" | head -n 1)"
    else
      set +e
      declare -g ${variable_name}="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
      set -e
    fi
  fi
  if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" >/dev/null 2>&1; then
    echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
    exit 1
  fi
  echo "${variable_name}=${!variable_name}"
}

export DEBIAN_FRONTEND=noninteractive

check_packages \
  bash-completion \
  ca-certificates \
  coreutils \
  curl \
  dirmngr \
  git \
  gnupg2

architecture="$(uname -m)"
case $architecture in
x86_64) architecture="amd64" ;;
aarch64 | armv8*) architecture="arm64" ;;
aarch32 | armv7* | armvhf*) architecture="arm" ;;
i?86) architecture="386" ;;
*)
  echo "(!) Architecture $architecture unsupported"
  exit 1
  ;;
esac

if [ "${KUBECTL_VERSION}" = "latest" ] || [ "${KUBECTL_VERSION}" = "lts" ] || [ "${KUBECTL_VERSION}" = "current" ] || [ "${KUBECTL_VERSION}" = "stable" ]; then
  KUBECTL_VERSION="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
else
  find_version_from_git_tags KUBECTL_VERSION https://github.com/kubernetes/kubernetes
fi
if [ "${KUBECTL_VERSION::1}" != 'v' ]; then
  KUBECTL_VERSION="v${KUBECTL_VERSION}"
fi
curl -sSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${architecture}/kubectl"
chmod 0755 /usr/local/bin/kubectl
if [ "$KUBECTL_SHA256" = "automatic" ]; then
  KUBECTL_SHA256="$(curl -sSL "https://dl.k8s.io/${KUBECTL_VERSION}/bin/linux/${architecture}/kubectl.sha256")"
fi
([ "${KUBECTL_SHA256}" = "dev-mode" ] || (echo "${KUBECTL_SHA256} */usr/local/bin/kubectl" | sha256sum -c -))
if ! type kubectl >/dev/null 2>&1; then
  echo '(!) kubectl installation failed!'
  exit 1
fi

kubectl completion bash >/etc/bash_completion.d/kubectl
