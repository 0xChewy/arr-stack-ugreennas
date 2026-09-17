FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Two RUN lines below pipe curl into a shell; without pipefail a failed
# download would be masked by the pipe's last command succeeding.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Node.js (for Claude Code + Playwright)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI + Compose plugin (to manage the project's docker-compose stack)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Python3 + PyYAML (for pre-commit YAML validation and fix-radarr-paths.sh)
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip \
    && pip3 install --no-cache-dir --break-system-packages pyyaml \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# sshpass (for NAS SSH access from scripts)
# dnsutils provides dig (for pre-commit domain checks)
RUN apt-get update && apt-get install -y --no-install-recommends \
      sshpass dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI — install as vscode user to avoid npm permission errors
USER vscode
RUN mkdir -p /home/vscode/.npm-global \
    && npm config set prefix /home/vscode/.npm-global \
    && npm install -g npm@latest \
    && npm install -g @anthropic-ai/claude-code
ENV PATH="/home/vscode/.npm-global/bin:${PATH}"
USER root

# Playwright system deps (for running e2e tests)
RUN npx playwright install-deps chromium

# End as the user VS Code connects as. Root was only needed for the package
# installs above; a container that starts as root is what trivy DS-0002 and
# hadolint DL3002 flag, and neither tool is wrong about it.
USER vscode
