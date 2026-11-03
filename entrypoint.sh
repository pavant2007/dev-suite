#!/bin/bash
set -euo pipefail

# OpenShift assigns a random UID: point the "coder" user at it so git/ssh/whoami work
# (sshd resolves the login name, so the entry must carry the current UID).
if [ "$(id -u)" != "$(id -u coder 2>/dev/null)" ] && [ -w /etc/passwd ]; then
  sed "/^coder:/d" /etc/passwd > /tmp/passwd
  echo "coder:x:$(id -u):0:coder:${HOME}:/bin/bash" >> /tmp/passwd
  cat /tmp/passwd > /etc/passwd && rm -f /tmp/passwd
fi
# Name any supplemental GIDs OpenShift added (e.g. the namespace fsGroup) so `groups`/`id` don't warn.
if [ -w /etc/group ]; then
  for gid in $(id -G); do
    getent group "$gid" >/dev/null || echo "ocp-${gid}:x:${gid}:coder" >> /etc/group
  done
fi

# Seed baked-in extensions into HOME (which may be an empty PVC on first start).
EXT_DIR="${HOME}/.local/share/code-server/extensions"
mkdir -p "${EXT_DIR}" "${HOME}/workspace"
cp -rn /opt/vscode-extensions/. "${EXT_DIR}/" 2>/dev/null || true

# Seed AI agent defaults (auto-approve) without overwriting user changes.
mkdir -p "${HOME}/.claude" "${HOME}/.codex"
cp -n /opt/agent-defaults/claude/settings.json "${HOME}/.claude/settings.json" 2>/dev/null || true
cp -n /opt/agent-defaults/codex/config.toml "${HOME}/.codex/config.toml" 2>/dev/null || true

# Non-root SSH server (key auth only) for Antigravity / VS Code Remote-SSH.
# Enabled when SSH_AUTHORIZED_KEYS is set or ~/.ssh/authorized_keys exists.
SSHD_DIR="${HOME}/.sshd"
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
  mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
  printf '%s\n' "${SSH_AUTHORIZED_KEYS}" > "${HOME}/.ssh/authorized_keys"
  chmod 600 "${HOME}/.ssh/authorized_keys"
fi
if [ -s "${HOME}/.ssh/authorized_keys" ]; then
  mkdir -p "${SSHD_DIR}"
  [ -f "${SSHD_DIR}/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N '' -f "${SSHD_DIR}/ssh_host_ed25519_key"
  cat > "${SSHD_DIR}/sshd_config" <<EOF
Port ${SSH_PORT:-2222}
HostKey ${SSHD_DIR}/ssh_host_ed25519_key
PidFile ${SSHD_DIR}/sshd.pid
AuthorizedKeysFile ${HOME}/.ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
StrictModes no
AllowTcpForwarding yes
X11Forwarding no
PrintMotd no
Subsystem sftp internal-sftp
SetEnv PATH=${PATH} JAVA_HOME=${JAVA_HOME} MAVEN_HOME=${MAVEN_HOME} GRADLE_HOME=${GRADLE_HOME} DISABLE_AUTOUPDATER=1
EOF
  /usr/sbin/sshd -f "${SSHD_DIR}/sshd_config" -D -e &
fi

# Auth: PASSWORD (or HASHED_PASSWORD) env enables password login; otherwise no auth.
AUTH=none
if [ -n "${PASSWORD:-}${HASHED_PASSWORD:-}" ]; then AUTH=password; fi

exec code-server \
  --bind-addr "0.0.0.0:${PORT:-8080}" \
  --auth "${AUTH}" \
  --disable-telemetry \
  --disable-update-check \
  --extensions-dir "${EXT_DIR}" \
  "$@"
