# dev-suite

A ready-to-use **browser VS Code** development environment for **OpenShift**. You deploy it into one namespace and open it from a browser. It already contains the tools for Java, Python, containers, Kubernetes, the major clouds and AI coding agents.

It runs under OpenShift's default `restricted-v2` security policy (non-root, random UID, no special permissions), so it also works on **Red Hat Developer Sandbox** and other clusters where you only have access to one namespace.

> **New here? Read the [User Manual](docs/USER_MANUAL.md).** It covers logging in, daily use, Docker on OpenShift, AI agents and troubleshooting.

## What's inside

| Area | Tools |
|---|---|
| Editor | code-server 4.144 (VS Code in the browser) with Java, Maven, Gradle, Python, Docker and YAML extensions |
| Java | Eclipse Temurin JDK 25, Maven 3.9, Gradle 9.8 |
| Python | Python 3.15 + pip, with FastAPI, uvicorn, pydantic, NumPy, pandas, ta, requests, httpx, PyYAML, pytest, ruff |
| Containers | Docker CLI 29 (+ buildx, compose). With no Docker daemon, `docker build / run / compose` run on OpenShift instead |
| Kubernetes | `kubectl` 1.37, `oc` 4.22 |
| Cloud | Google Cloud CLI (`gcloud`, `gsutil`, `bq`, GKE auth plugin), AWS CLI v2 |
| AI agents | Claude Code, OpenAI Codex CLI (preconfigured to run without approval prompts) |
| Other | Git, OpenSSH server (for Antigravity / VS Code Remote-SSH), WireGuard tools, jq, ripgrep |

Image: **`ghcr.io/pavant2007/dev-suite:latest`**. It's public, linux/amd64, about 1.6 GB.

## Quick start (5 minutes)

You need the `oc` CLI and access to an OpenShift namespace.

```bash
git clone https://github.com/pavant2007/dev-suite.git && cd dev-suite

# 1. Set your login password (this file is git-ignored)
cp openshift/secret.example.yaml openshift/secret.yaml
#    edit openshift/secret.yaml -> password: "<your-strong-password>"

# 2. Deploy into your namespace
oc login ...                              # as a user who is admin of the namespace
oc apply -k openshift/ -n <your-namespace>

# 3. Open it
oc get route vscode -n <your-namespace> -o jsonpath='https://{.spec.host}{"\n"}'
```

Open the URL and enter your password. Your files in `/home/coder` live on a persistent volume and survive restarts.

To try it locally (no OpenShift features):

```bash
docker run --rm -p 8080:8080 -e PASSWORD='<your-password>' ghcr.io/pavant2007/dev-suite:latest
# open http://localhost:8080
```

## Repository layout

```
Dockerfile                  # multi-stage build of the image
entrypoint.sh               # startup: OpenShift UID handling, seeds extensions/agent config, starts sshd + code-server
requirements.txt            # Python libraries baked into the image
bin/
  docker                    # docker wrapper: real CLI when a daemon exists, else maps to OpenShift
  ocp-build                 # docker build -> OpenShift Build
  ocp-compose               # docker compose -> Deployments/Services/Routes
agent-defaults/             # Claude Code / Codex auto-approve defaults (copied to $HOME once)
openshift/                  # deployment manifests (oc apply -k openshift/)
  secret.example.yaml       #   copy to secret.yaml: password, SSH keys, API keys
  rbac.yaml                 #   lets the pod run builds and deploy in its own namespace
  deployment.yaml service.yaml route.yaml pvc.yaml serviceaccount.yaml kustomization.yaml
  dind-sidecar-patch.yaml   #   optional real Docker daemon (needs privileged pods, not on Sandbox)
ci/smoke-test.sh            # image tests run in CI
.github/workflows/build-image.yml
docs/USER_MANUAL.md
```

## How the image is built

GitHub Actions ([build-image.yml](.github/workflows/build-image.yml)) runs on GitHub-hosted x86 runners for every push to `main`, every `v*` tag and every pull request:

1. builds the linux/amd64 image, with layers cached between runs
2. runs [ci/smoke-test.sh](ci/smoke-test.sh) as a random OpenShift-style UID: every tool's version, the Python imports, code-server login, SSH login and agent defaults
3. pushes `latest`, `sha-<commit>` and `vX.Y.Z` tags to GHCR. Pull requests only build and test.

You can also run it by hand: **Actions → build-image → Run workflow**. Tool versions are build arguments at the top of the [Dockerfile](Dockerfile).

Building locally works, but it's slow on Apple Silicon because amd64 is emulated:

```bash
docker build --platform linux/amd64 -t dev-suite:local . && ci/smoke-test.sh dev-suite:local
```

## Security notes

- **Never commit secrets.** `openshift/secret.yaml` and `.env` are git-ignored. Only `secret.example.yaml`, which holds placeholders, belongs in git.
- The pod runs **non-root** with no added capabilities. Its service account gets the namespace-scoped `edit` role (see [rbac.yaml](openshift/rbac.yaml)), so tools and agents inside it can manage that namespace and nothing else.
- Claude Code and Codex are set to **auto-approve**, so they can run commands and edit files in the dev box without asking. Treat the dev box as their sandbox, and don't put credentials in it that you wouldn't give an agent.
- The image is built without provenance or SBOM attestations, and CI uploads no build records, so no commit metadata is published with it.

See the [User Manual](docs/USER_MANUAL.md) for everything else.
