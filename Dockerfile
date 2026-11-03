# syntax=docker/dockerfile:1.7
#
# Lightweight browser-based VS Code (code-server) dev image for OpenShift (OCP).
# Ubuntu 24.04 LTS | code-server + extensions | Docker CLI (+buildx, compose)
# Maven | Gradle | Git | JDK 25 (Temurin) | Python 3.x latest + FastAPI/NumPy/pandas/ta | WireGuard tools
# AI agents: Claude Code, OpenAI Codex | SSH server for Antigravity Remote-SSH
# Cloud/K8s CLIs: kubectl, oc (OpenShift), gcloud (+gsutil, bq, GKE auth plugin), aws v2
#
# Build (x86_64):  docker build --platform linux/amd64 -t vscode-dev:latest .

ARG UBUNTU_VERSION=24.04

# ---------- Source stages (only binaries are copied out of these) ----------
FROM --platform=linux/amd64 eclipse-temurin:25-jdk-noble AS jdk
FROM --platform=linux/amd64 docker:29-cli               AS dockercli
FROM --platform=linux/amd64 ghcr.io/astral-sh/uv:0.13.6 AS uv

# ---------- Cloud CLI stage (built in parallel with the fetch stage) ----------
FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION} AS cloud

ARG KUBECTL_VERSION=v1.37.2
# OpenShift client channel on mirror.openshift.com: "stable", "stable-4.22", or an exact version like "4.22.18"
ARG OC_CHANNEL=stable

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

# kubectl (checksum-verified)
RUN curl -fsSLo /opt/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  /opt/kubectl" | sha256sum -c - \
 && chmod 0755 /opt/kubectl

# oc - OpenShift CLI
RUN curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_CHANNEL}/openshift-client-linux-amd64-rhel9.tar.gz" \
    | tar -xz -C /opt oc \
 && chmod 0755 /opt/oc

# Google Cloud CLI (gcloud, gsutil, bq) + GKE kubectl auth plugin, trimmed
RUN curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz \
    | tar -xz -C /opt \
 && /opt/google-cloud-sdk/bin/gcloud components install gke-gcloud-auth-plugin --quiet \
 && rm -rf /opt/google-cloud-sdk/.install/.backup /root/.config /tmp/* \
 && find /opt/google-cloud-sdk -depth -type d -name __pycache__ -exec rm -rf {} +

# AWS CLI v2
RUN curl -fsSLo /tmp/awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
 && unzip -q /tmp/awscli.zip -d /tmp \
 && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
 && rm -rf /tmp/aws /tmp/awscli.zip

# ---------- Fetch stage: download & unpack tools, pre-install extensions ----------
FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION} AS fetch

ARG MAVEN_VERSION=3.9.16
ARG GRADLE_VERSION=9.8.2
ARG CODE_SERVER_VERSION=4.144.0
ARG CLAUDE_VERSION=latest
ARG CODEX_VERSION=0.166.0
# "3" = latest available CPython 3.x; pin e.g. 3.14 if required
ARG PYTHON_VERSION=3
ARG EXTENSIONS="\
redhat.java \
vscjava.vscode-java-debug \
vscjava.vscode-java-test \
vscjava.vscode-java-dependency \
vscjava.vscode-maven \
vscjava.vscode-gradle \
ms-python.python \
ms-python.debugpy \
ms-azuretools.vscode-docker \
redhat.vscode-yaml"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip jq \
 && rm -rf /var/lib/apt/lists/*

# Maven
RUN mkdir -p /opt/maven \
 && curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    | tar -xz --strip-components=1 -C /opt/maven

# Gradle
RUN curl -fsSLo /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
 && unzip -q /tmp/gradle.zip -d /opt \
 && mv "/opt/gradle-${GRADLE_VERSION}" /opt/gradle \
 && rm /tmp/gradle.zip

# code-server (standalone tarball ships its own Node runtime)
RUN mkdir -p /opt/code-server \
 && curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz --strip-components=1 -C /opt/code-server

# Claude Code (native binary, checksum-verified against the release manifest)
RUN B=https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases \
 && V="${CLAUDE_VERSION}"; [ "$V" = latest ] && V="$(curl -fsSL "$B/latest")" \
 && SUM="$(curl -fsSL "$B/$V/manifest.json" | jq -r '.platforms["linux-x64"].checksum')" \
 && curl -fsSLo /opt/claude "$B/$V/linux-x64/claude" \
 && echo "${SUM}  /opt/claude" | sha256sum -c - \
 && chmod 0755 /opt/claude

# OpenAI Codex CLI (static musl binary)
RUN curl -fsSL "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C /tmp \
 && install -m 0755 /tmp/codex-x86_64-unknown-linux-musl /opt/codex \
 && rm -f /tmp/codex-*

# Python (relocatable CPython build via uv), trimmed of test suites and caches
COPY --from=uv /uv /usr/local/bin/uv
RUN UV_PYTHON_INSTALL_DIR=/opt/python uv python install "${PYTHON_VERSION}" \
 && PY_BIN="$(UV_PYTHON_INSTALL_DIR=/opt/python uv python find "${PYTHON_VERSION}")" \
 && PY_HOME="$(dirname "$(dirname "$(readlink -f "${PY_BIN}")")")" \
 && ln -s "${PY_HOME}" /opt/python/current \
 && rm -f "${PY_HOME}"/lib/python3*/EXTERNALLY-MANAGED \
 && { /opt/python/current/bin/python3 -m pip --version || /opt/python/current/bin/python3 -m ensurepip; } \
 && find "${PY_HOME}" -depth \( -name test -o -name tests -o -name idle_test -o -name __pycache__ \) -type d -exec rm -rf {} + \
 && rm -rf /opt/python/.cache /opt/python/.lock

# Python libraries (FastAPI, NumPy, pandas, ta, ...) from requirements.txt
COPY requirements.txt /tmp/requirements.txt
RUN /opt/python/current/bin/python3 -m pip install --no-cache-dir --upgrade pip \
 && /opt/python/current/bin/python3 -m pip install --no-cache-dir -r /tmp/requirements.txt \
 && find /opt/python/current/ -depth -type d \( -name __pycache__ -o -name tests -o -name test \) -path '*site-packages*' -exec rm -rf {} + \
 && rm -f /tmp/requirements.txt

# Bake extensions into a seed dir; entrypoint copies them into $HOME on first start
# (so they survive a PVC mounted on /home/coder).
RUN for ext in ${EXTENSIONS}; do \
      /opt/code-server/bin/code-server --extensions-dir /opt/vscode-extensions --install-extension "${ext}" || exit 1; \
    done \
 && rm -rf /root/.local /root/.config /root/.cache /tmp/*

# ---------- Final runtime image ----------
FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.title="vscode-dev" \
      org.opencontainers.image.description="code-server dev image: JDK 25, Maven, Gradle, Python 3, Docker CLI, Git" \
      io.openshift.expose-services="8080:http" \
      io.k8s.display-name="VS Code Server (code-server)"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    JAVA_HOME=/opt/java/openjdk \
    MAVEN_HOME=/opt/maven \
    GRADLE_HOME=/opt/gradle \
    DISABLE_AUTOUPDATER=1 \
    CLOUDSDK_CORE_DISABLE_USAGE_REPORTING=true \
    CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK=true \
    USE_GKE_GCLOUD_AUTH_PLUGIN=True \
    AWS_PAGER="" \
    HOME=/home/coder \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/opt/java/openjdk/bin:/opt/maven/bin:/opt/gradle/bin:/opt/python/current/bin:/opt/code-server/bin:/opt/google-cloud-sdk/bin:/opt/aws-cli/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Minimal OS packages only
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client openssh-server tini \
      less procps unzip nano jq ripgrep wireguard-tools iproute2 \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/*

COPY --from=jdk       /opt/java/openjdk /opt/java/openjdk
COPY --from=dockercli /usr/local/bin/docker /usr/local/libexec/docker-cli/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
COPY --from=fetch     /opt/maven            /opt/maven
COPY --from=fetch     /opt/gradle           /opt/gradle
COPY --from=fetch     /opt/python           /opt/python
COPY --from=fetch     /opt/code-server      /opt/code-server
COPY --from=fetch     /opt/vscode-extensions /opt/vscode-extensions
COPY --from=fetch     /opt/claude           /usr/local/bin/claude
COPY --from=fetch     /opt/codex            /usr/local/bin/codex
COPY --from=cloud     /opt/kubectl          /usr/local/bin/kubectl
COPY --from=cloud     /opt/oc               /usr/local/bin/oc
COPY --from=cloud     /opt/google-cloud-sdk /opt/google-cloud-sdk
COPY --from=cloud     /opt/aws-cli          /opt/aws-cli
COPY                  agent-defaults/       /opt/agent-defaults/
COPY --chmod=0755     entrypoint.sh         /usr/local/bin/entrypoint.sh
# docker wrapper: build/run/compose map onto OpenShift (ocp-build, oc run, ocp-compose) when no daemon is reachable
COPY --chmod=0755     bin/docker bin/ocp-build bin/ocp-compose /usr/local/bin/

# OpenShift runs containers with a random UID in group 0:
# make HOME and /etc/passwd group-0 writable so any UID works.
RUN ln -s /opt/python/current/bin/python3 /usr/local/bin/python \
 && ln -sf /opt/python/current/bin/pip3 /usr/local/bin/pip3 \
 && ln -sf /opt/python/current/bin/pip3 /usr/local/bin/pip \
 && useradd --uid 1001 --gid 0 --home-dir /home/coder --create-home --shell /bin/bash coder \
 && mkdir -p /home/coder/workspace /run/sshd \
 && rm -f /etc/ssh/ssh_host_* \
 && chgrp -R 0 /home/coder /opt/vscode-extensions \
 && chmod -R g=u /home/coder /opt/vscode-extensions \
 && chmod g=u /etc/passwd /etc/group

USER 1001
WORKDIR /home/coder/workspace
EXPOSE 8080 2222

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["/home/coder/workspace"]
