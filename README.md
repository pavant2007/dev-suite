# dev-suite — code-server dev image for OpenShift

Browser VS Code (code-server) on Ubuntu 24.04, x86_64 (linux/amd64).

| Tool | Version (build arg) |
|------|---------------------|
| code-server | 4.144.0 (`CODE_SERVER_VERSION`) |
| JDK | Eclipse Temurin 25 |
| Maven | 3.9.16 (`MAVEN_VERSION`) |
| Gradle | 9.8.2 (`GRADLE_VERSION`) |
| Python | latest 3.x (`PYTHON_VERSION=3`, e.g. `3.14` to pin) + pip/pip3 |
| Python libs | `requirements.txt`: fastapi[standard], uvicorn, pydantic, numpy, pandas, ta, requests, httpx, python-dotenv, pytest, ruff |
| Docker | CLI 29 + buildx + compose; without a daemon `docker build/run/compose` run on OpenShift |
| Git | Ubuntu 24.04 package |
| Claude Code | latest native binary (`CLAUDE_VERSION`), checksum-verified |
| OpenAI Codex CLI | 0.166.0 (`CODEX_VERSION`) |
| kubectl | v1.37.2 (`KUBECTL_VERSION`), checksum-verified |
| oc (OpenShift CLI) | stable channel, currently 4.22.18 (`OC_CHANNEL`) |
| Google Cloud CLI | latest `gcloud`, `gsutil`, `bq` + `gke-gcloud-auth-plugin` |
| AWS CLI | v2 latest |
| WireGuard | `wireguard-tools` (`wg`, `wg-quick`) + `iproute2` |
| OpenSSH server | for Antigravity Remote-SSH (non-root, key-only, port 2222) |

Extensions baked in (`EXTENSIONS` build arg): Java pack (redhat.java, debug, test, dependency, Maven, Gradle), Python + debugpy, Docker, YAML.

How it stays small: multi-stage build (the cloud CLIs build in a parallel stage), only the binaries are copied out, no compilers or apt caches, Python test suites stripped. Docker is the CLI only — the daemon runs in an optional sidecar.

## Files

```
.github/workflows/build-image.yml   # CI: build, smoke test, push to GHCR
ci/smoke-test.sh
Dockerfile, entrypoint.sh, requirements.txt, .dockerignore
agent-defaults/            # auto-approve configs seeded into $HOME on first start
  claude/settings.json     # permissions.defaultMode = bypassPermissions
  codex/config.toml        # approval_policy = never, sandbox_mode = danger-full-access
openshift/
  kustomization.yaml       # oc apply -k openshift/
  secret.example.yaml      # copy to secret.yaml (git-ignored): password, SSH keys, API keys
  rbac.yaml                # RoleBinding: vscode SA -> edit (lets it run OpenShift builds)
  serviceaccount.yaml  pvc.yaml  deployment.yaml  service.yaml  route.yaml
  dind-sidecar-patch.yaml  # optional Docker daemon sidecar (privileged)
```

## Build (GitHub Actions)

[`.github/workflows/build-image.yml`](.github/workflows/build-image.yml) runs on GitHub-hosted x86 runners for each push to `main`, each `v*` tag and each PR. It:

1. builds the linux/amd64 image, with layers cached between runs in the GitHub Actions cache
2. runs [`ci/smoke-test.sh`](ci/smoke-test.sh): every tool's version, the Python imports, code-server login, and SSH, all as a random OpenShift UID
3. pushes to **`ghcr.io/pavant2007/dev-suite`** with the tags `latest`, `sha-<commit>` and `vX.Y.Z` (PRs build and test only)

You can trigger it by hand from Actions → build-image → Run workflow.

**Public image:** `ghcr.io/pavant2007/dev-suite` is public, so anyone can pull it without logging in, and OpenShift doesn't need a pull secret:

```bash
docker pull ghcr.io/pavant2007/dev-suite:latest
```

Local build (slow on Apple Silicon because amd64 is emulated): `docker build --platform linux/amd64 -t dev-suite:local . && ci/smoke-test.sh dev-suite:local`

## Deploy

```bash
cp openshift/secret.example.yaml openshift/secret.yaml   # git-ignored: set password, SSH key, API keys
oc apply -k openshift/ -n vscode
oc get route vscode -n vscode -o jsonpath='https://{.spec.host}{"\n"}'
```

`/home/coder` sits on a PVC, so the workspace, settings, extensions and the `~/.m2` and `~/.gradle` caches survive restarts.

### AI agents (auto-approve)

Claude Code and Codex start in auto-approve mode: no permission prompts and full access to the container. The pod itself still runs non-root under `restricted-v2`, so the agents can't affect the node or the cluster. The defaults are copied into `~/.claude/settings.json` and `~/.codex/config.toml` only if those files don't already exist, so your own edits are kept.

To log in, open the code-server terminal and run `claude` and `codex login`, or put the API keys in `secret.yaml`.

### Antigravity (Remote-SSH)

Antigravity installs its own server (`~/.antigravity-server`) over SSH the first time it connects, and that server must match the client's version, so it can't be built into the image. The image provides what Antigravity needs to install it: sshd, tar, curl and a writable, persistent home directory.

1. Put your public key into `ssh-authorized-keys` in `openshift/secret.yaml` and apply.
2. `oc port-forward svc/vscode 2222:2222 -n vscode`
3. Add to `~/.ssh/config` on your machine:
   ```
   Host ocp-vscode
     HostName localhost
     Port 2222
     User coder
   ```
4. In Antigravity: Remote-SSH → Connect to Host → `ocp-vscode`.
5. For full agent permissions, set the agent's terminal-execution and review policies to "Always proceed" in Antigravity's settings. These are client-side settings.

### WireGuard

The `wg` and `wg-quick` tools are installed, and the WireGuard kernel module comes from the node (RHCOS ships it). Bringing up a tunnel inside the pod needs root plus the `NET_ADMIN` capability, which `restricted-v2` doesn't allow. A cluster admin has to grant a custom SCC for that. Without one, use `wg genkey` and similar commands for key and config work only.

### Docker on OpenShift (no daemon needed)

OpenShift's default `restricted-v2` policy can't run a Docker daemon, and neither can rootless Podman (seccomp blocks user namespaces). The image therefore ships a `docker` wrapper that maps the everyday commands onto OpenShift in the pod's own namespace:

| Command | What happens on OpenShift |
|---|---|
| `docker build -t myapp:v1 .` | [`ocp-build`](bin/ocp-build): OpenShift Docker-strategy build, pushed to `image-registry.openshift-image-registry.svc:5000/<ns>/myapp:v1` |
| `docker run [--rm] [-it] [-e K=V] IMAGE [ARGS]` | `oc run` pod, attached; `myapp:v1` resolves to the namespace image |
| `docker run -d --name web -p 8080 IMAGE` | detached pod + Service `web:8080` (other pods reach `http://web:8080`) |
| `docker ps` / `logs` / `exec -it` / `stop` / `rm` | `oc get pods` / `logs` / `exec` / `delete` |
| `docker images` | the namespace's ImageStreamTags |
| `docker compose up -d` / `down` / `ps` / `logs SVC` | [`ocp-compose`](bin/ocp-compose): builds `build:` services, then one Deployment + Service per service (same names, so services reach each other as in compose); published ports get an HTTPS Route; named volumes become 1Gi PVCs |
| anything else | the real Docker CLI, used as-is whenever `DOCKER_HOST` is set or a daemon socket exists |

Limits: images must run as a non-root, random UID (official `nginx`, `postgres`, `redis` images don't; use `nginxinc/nginx-unprivileged`, `registry.redhat.io`/UBI or Bitnami variants). Bind mounts, `depends_on`, `privileged` and `user` are ignored. There is no `-p HOST:CONTAINER` port on your laptop; use the Route URL or `oc port-forward`.

`-f`, `--build-arg` and `-t` are supported. The pod's service account needs build rights in its namespace, which `rbac.yaml` grants.

**Developer Sandbox:** you have namespace access but no cluster access. The RoleBinding has to be created by your own user (namespace admin), not by a service account:

```bash
oc login --web https://api.<sandbox-cluster>:6443
oc apply -f openshift/rbac.yaml -n <your-namespace>
```

Or run the pod as an existing SA that can already build: `oc patch deploy vscode -p '{"spec":{"template":{"spec":{"serviceAccountName":"<sa>"}}}}'`.

### Optional: Docker daemon sidecar (not on Developer Sandbox)

The restricted SCC does not allow a Docker daemon. If your cluster policy allows privileged pods:

```bash
oc adm policy add-scc-to-user privileged -z vscode -n vscode
# uncomment the `patches:` block in openshift/kustomization.yaml, then:
oc apply -k openshift/ -n vscode
```

If you can't get privileged pods, set `DOCKER_HOST` to a remote Docker host instead, or build images with OpenShift BuildConfigs.

## Run locally (smoke test)

```bash
docker run --rm -p 8080:8080 -e PASSWORD='<your-password>' vscode-dev:latest
# open http://localhost:8080
```
