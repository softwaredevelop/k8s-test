ARG VARIANT=latest
FROM docker.io/library/alpine:$VARIANT

ARG USERNAME=codespace
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# ENV DEBIAN_FRONTEND=noninteractive

COPY library-scripts/* /tmp/scripts/

RUN \
    apk update; \
    apk add --no-cache \
    bash; \
    bash /tmp/scripts/common.sh "true" "alpine"; \
    bash /tmp/scripts/setup-user.sh "${USERNAME}" "${USER_UID}" "${USER_GID}" "alpine"; \
    bash /tmp/scripts/hadolint.sh "2.10.0" "alpine"; \
    bash /tmp/scripts/shfmt.sh "3.5.1" "alpine"; \
    bash /tmp/scripts/shellcheck.sh "0.8.0" "alpine"; \
    bash /tmp/scripts/editorconfig.sh "2.6.0" "alpine"; \
    bash /tmp/scripts/trivy.sh "0.30.4" "alpine"; \
    bash /tmp/scripts/kubectl-helm.sh "alpine"; \
    bash /tmp/scripts/docker-from-docker.sh "alpine"; \
    apt-get autoremove; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/scripts
