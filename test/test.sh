#!/usr/bin/env bash

SCRIPT_FOLDER_NAME=$(dirname $0)
cd ${SCRIPT_FOLDER_NAME} || exit

# shellcheck source=/dev/null
source test-utils.sh codespace

check "non-root-user" non_root_user
check "hadolint" hadolint --version
check "shfmt" shfmt --version
check "shellcheck" shellcheck --version
check "editorconfig" ec --version
check "trivy" trivy --version
check "kubectl" kubectl version --client --output=yaml
check "helm" helm version --client --short
check "minikube" minikube version

reportResults
