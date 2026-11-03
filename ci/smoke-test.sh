#!/bin/bash
# Smoke test for the image. Runs as a random OpenShift-style UID in group 0.
# Usage: ci/smoke-test.sh <image>
set -euo pipefail
IMAGE="${1:-dev-suite:test}"
UID_GID="1000870000:0"
TMP="$(mktemp -d)"
cleanup() {
  rc=$?
  if [ "$rc" != 0 ]; then echo "--- container logs (failure) ---"; docker logs vsc-smoke 2>&1 | tail -40 || true; fi
  docker rm -f vsc-smoke >/dev/null 2>&1 || true; rm -rf "$TMP"
}
trap cleanup EXIT

docker image inspect "$IMAGE" --format '{{.Size}}' | awk '{printf "image size: %.2f GB\n", $1/1e9}'

echo "--- tool versions ---"
docker run --rm --user "$UID_GID" --entrypoint bash "$IMAGE" -ec '
echo "arch=$(uname -m) os=$(. /etc/os-release; echo $PRETTY_NAME) uid=$(id -u) gid=$(id -g)"
java -version 2>&1 | head -1
mvn -v | head -1
gradle -v | grep ^Gradle
python3 --version
pip3 --version | cut -d" " -f1-2
python3 -c "import fastapi, numpy, pandas, ta, uvicorn, pydantic, requests, httpx; print(\"python libs OK: fastapi\", fastapi.__version__, \"numpy\", numpy.__version__, \"pandas\", pandas.__version__)"
git --version
docker --version
ocp-build --help | head -1
docker compose version
docker buildx version | cut -d" " -f1-2
echo "code-server $(code-server --version 2>/dev/null | grep -m1 -E "^[0-9]+\.")"
claude --version
codex --version
kubectl version --client | head -1
oc version --client | head -1
gcloud --version | head -1
gke-gcloud-auth-plugin --version | head -1
aws --version
wg --version
echo "extensions: $(ls /opt/vscode-extensions | grep -v json | sed -E "s/-[0-9]+\..*//" | sort -u | tr "\n" " ")"
'

echo "--- code-server + sshd ---"
ssh-keygen -q -t ed25519 -N '' -f "$TMP/key"
docker run -d --name vsc-smoke --user "$UID_GID" --group-add 1000870000 -p 18080:8080 -p 12222:2222 \
  -e PASSWORD='smoke-test-pw' -e SSH_AUTHORIZED_KEYS="$(cat "$TMP/key.pub")" "$IMAGE" >/dev/null

for _ in $(seq 1 60); do curl -fs localhost:18080/healthz >/dev/null && break; sleep 2; done
curl -fs localhost:18080/healthz && echo
bad=$(curl -s -o /dev/null -w '%{http_code}' -d 'password=wrong' localhost:18080/login)
good=$(curl -s -o /dev/null -w '%{http_code}' -d 'password=smoke-test-pw' localhost:18080/login)
echo "login: wrong password -> $bad, right password -> $good"
[ "$good" = 302 ] && [ "$bad" != 302 ]

for _ in $(seq 1 15); do nc -z localhost 12222 2>/dev/null && break; sleep 1; done
ssh -i "$TMP/key" -p 12222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR coder@localhost '
echo "ssh OK as $(whoami) uid=$(id -u), java at $(command -v java)"
echo "seeded extensions: $(ls ~/.local/share/code-server/extensions | grep -vc json)"
grep -q "approval_policy = \"never\"" ~/.codex/config.toml && echo "codex auto-approve: OK"
grep -q bypassPermissions ~/.claude/settings.json && echo "claude auto-approve: OK"
! groups 2>&1 | grep -q "cannot find name" && echo "groups: OK ($(groups))"
'
echo "SMOKE TEST PASSED"
