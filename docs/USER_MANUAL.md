# dev-suite User Manual

This manual explains how to use the dev-suite browser IDE on OpenShift. Part A is for everyone who uses the dev box. Part B is for the person who deploys and maintains it. Part C covers problems and their fixes.

**Contents**

- Part A: Using the dev box
  1. [Logging in](#1-logging-in)
  2. [Your workspace and what is saved](#2-your-workspace-and-what-is-saved)
  3. [Java: Maven and Gradle](#3-java-maven-and-gradle)
  4. [Python and FastAPI](#4-python-and-fastapi)
  5. [Git and GitHub](#5-git-and-github)
  6. [Docker on OpenShift](#6-docker-on-openshift)
  7. [Deploying your app with oc](#7-deploying-your-app-with-oc)
  8. [AI agents: Claude Code and Codex](#8-ai-agents-claude-code-and-codex)
  9. [Cloud CLIs: gcloud and aws](#9-cloud-clis-gcloud-and-aws)
  10. [Connecting from Antigravity or desktop VS Code (SSH)](#10-connecting-from-antigravity-or-desktop-vs-code-ssh)
  11. [WireGuard](#11-wireguard)
- Part B: Deploying and maintaining
  12. [First-time deployment](#12-first-time-deployment)
  13. [Changing the password, SSH keys or API keys](#13-changing-the-password-ssh-keys-or-api-keys)
  14. [Updating to a new image](#14-updating-to-a-new-image)
  15. [Resources and storage](#15-resources-and-storage)
  16. [Customizing the image](#16-customizing-the-image)
- Part C: [Troubleshooting](#part-c-troubleshooting)

---

## Part A: Using the dev box

### 1. Logging in

1. Open the dev box URL (the OpenShift Route, `https://vscode-<namespace>.apps.<cluster-domain>`). If you don't know it, ask whoever deployed it, or run `oc get route vscode -o jsonpath='{.spec.host}'`.
2. Enter the password. code-server shows a login page, not an OpenShift login.
3. VS Code opens in the browser, in the folder `/home/coder/workspace`.

Open a terminal with **Terminal → New Terminal** (or <kbd>Ctrl</kbd>+<kbd>`</kbd>). You are user `coder`. OpenShift assigns a random numeric user ID, which is normal.

> Restarting or updating the pod closes open terminals. Afterwards, reload the browser tab. Your files are kept.

### 2. Your workspace and what is saved

Everything under **`/home/coder`** is on a persistent volume and survives restarts and image updates:

| Path | What it holds |
|---|---|
| `~/workspace` | your projects (put your code here) |
| `~/.m2`, `~/.gradle` | Maven and Gradle download caches |
| `~/.local` | Python packages you install with `pip install`, plus VS Code extensions and settings |
| `~/.claude`, `~/.codex` | AI agent logins and settings |
| `~/.ssh`, `~/.gitconfig` | your SSH and Git configuration |

Anything outside `/home/coder` (such as `/opt` or `/usr`) comes from the image and is reset on every update. Don't keep files there.

**Installing extra VS Code extensions:** use the Extensions panel as usual. Extensions come from Open VSX, not the Microsoft Marketplace, and are saved in your home folder.

**Installing extra tools:** `apt install` doesn't work, because the dev box isn't root. Use:
- `pip install <package>` for Python packages (installed to `~/.local`)
- a single-binary download into `~/bin` for anything else:
  ```bash
  mkdir -p ~/bin && export PATH=~/bin:$PATH   # add the export to ~/.bashrc
  ```
- or ask for the tool to be added to the image (see [section 16](#16-customizing-the-image)).

### 3. Java: Maven and Gradle

JDK 25, Maven and Gradle are on the `PATH`, and `JAVA_HOME` is already set.

```bash
java -version
mvn -v
gradle -v
```

Create and run a Spring Boot or plain Maven project:

```bash
cd ~/workspace
mvn archetype:generate -DgroupId=com.example -DartifactId=demo \
    -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
cd demo && mvn package && java -cp target/demo-1.0-SNAPSHOT.jar com.example.App
```

The Java extension pack gives you code completion, debugging (F5), tests (Testing panel), Maven and Gradle views. The first time you open a Java project, give the Java language server a minute to index it.

Maven and Gradle use at most half of the container's memory (`MAVEN_OPTS` / `GRADLE_OPTS` are preset), so builds don't push the pod over its memory limit.

### 4. Python and FastAPI

```bash
python3 --version          # also: python, pip, pip3
python3 -c "import fastapi, numpy, pandas, ta; print('ok')"
```

**Run a FastAPI app:**

```bash
mkdir -p ~/workspace/api && cd ~/workspace/api
cat > main.py <<'EOF'
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def hello():
    return {"hello": "world"}
EOF
fastapi dev main.py --host 0.0.0.0 --port 8000
```

code-server forwards ports for you. Open `https://<dev-box-url>/proxy/8000/` in the browser. Use `/absproxy/8000/` instead if your app expects to run at the root path.

**Project environments:** prefer a virtual environment per project:

```bash
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
```

### 5. Git and GitHub

Set your identity once (saved in your home folder):

```bash
git config --global user.name  "Your Name"
git config --global user.email "<id>+<user>@users.noreply.github.com"   # GitHub "noreply" address keeps your email private
```

**HTTPS with a token:** when `git push` asks for a password, use a GitHub personal access token with only the scopes you need, never your account password. To avoid typing it every time:

```bash
git config --global credential.helper store   # stores it in ~/.git-credentials (on your volume)
```

**SSH:** create a key with `ssh-keygen -t ed25519`, add `~/.ssh/id_ed25519.pub` to GitHub, then clone with `git@github.com:...`.

> Never commit tokens, passwords, `.env` files or kubeconfigs. Add them to `.gitignore`.

### 6. Docker on OpenShift

A Docker daemon can't run inside an OpenShift pod under the default security policy, and the same is true on Developer Sandbox. So the `docker` command in the dev box is a wrapper that does the same job using OpenShift, in your own namespace:

| You type | What actually happens |
|---|---|
| `docker build -t myapp:v1 .` | an OpenShift Build of the current folder's `Dockerfile`; the image is stored in your namespace's registry |
| `docker images` | lists images in your namespace |
| `docker run --rm myapp:v1` | runs the image as a pod and shows its output |
| `docker run -it --rm myapp:v1 sh` | interactive shell in a new pod |
| `docker run -d --name web -p 8080 myapp:v1` | runs in the background and creates a service `web:8080` |
| `docker ps` | lists pods |
| `docker logs web` / `docker exec -it web sh` | pod logs / shell inside the pod |
| `docker stop web` / `docker rm web` | deletes the pod and its service |
| `docker compose up -d` | builds and starts every service in `compose.yaml` |
| `docker compose ps` / `logs SERVICE` / `down` | status / logs / remove everything |

#### Build and run an image

```bash
cd ~/workspace/myapp
docker build -t myapp:v1 .          # watch the build log; ends with "Image: ...myapp:v1"
docker run --rm myapp:v1            # run once and print output
docker run -d --name myapp -p 8080 myapp:v1
curl http://myapp:8080/             # reachable by name from the dev box and other pods
docker stop myapp
```

Supported `docker build` options: `-t`, `-f` (Dockerfile path inside the folder), `--build-arg`. Options like `--platform` or `--no-cache` are accepted and ignored.

Supported `docker run` options: `-d`, `--rm`, `-it`, `--name`, `-e KEY=VALUE`, `-p PORT`, and arguments after the image name. `-v` volumes and `--user` are ignored.

#### Docker Compose

Given a `compose.yaml` like:

```yaml
services:
  api:
    build: ./api               # built on OpenShift
    ports: ["8000:8000"]       # published -> gets a public HTTPS URL
    environment:
      DB_HOST: db
  db:
    image: quay.io/sclorg/postgresql-16-c9s   # public, OpenShift-friendly image
    environment:
      POSTGRESQL_USER: app
      POSTGRESQL_PASSWORD: app
      POSTGRESQL_DATABASE: app
    volumes: ["dbdata:/var/lib/pgsql/data"]          # named volume -> 1 GB persistent volume
volumes:
  dbdata:
```

```bash
docker compose up -d       # build + deploy; prints deployments, services and the public route
docker compose ps
docker compose logs api
docker compose down        # remove (add -v to also delete the volumes)
```

Services reach each other by service name (`http://api:8000`, `db:5432`), just as with Docker Compose. Published ports get an HTTPS Route; see `oc get route` for the URL.

Not supported or ignored: bind mounts (`./src:/app`; copy files into the image instead), `depends_on`, `restart`, `privileged`, `user`, `network_mode`.

#### Important: images must run as non-root

OpenShift runs every container as a random, non-root user. Many Docker Hub images expect root and crash or fail with "permission denied". Use OpenShift-friendly versions:

| Instead of | Use |
|---|---|
| `nginx` | `nginxinc/nginx-unprivileged` (listens on 8080) |
| `postgres` | `quay.io/sclorg/postgresql-16-c9s` (env `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD`, `POSTGRESQL_DATABASE`) |
| `redis` | `quay.io/sclorg/redis-7-c9s` |
| `mysql` | `quay.io/sclorg/mysql-80-c9s` |
| `ubuntu`, `debian`, `alpine` (as a base image) | fine to build from, but don't write to root-owned paths at runtime; make app folders group-writable (`chgrp -R 0 /app && chmod -R g=u /app`) |

There's also no way to open `-p 8080:80` on your laptop. Use the Route URL, or `oc port-forward pod/NAME 8080:80` from your own machine.

#### Using a real Docker daemon instead

If you have a Docker host you can reach, `export DOCKER_HOST=tcp://<host>:2375` (or `ssh://user@host`). The `docker` command then becomes the real Docker CLI for that session.

### 7. Deploying your app with oc

`oc` and `kubectl` are already logged in to your namespace, using the pod's service account.

```bash
oc whoami                               # system:serviceaccount:<namespace>:<sa>
oc get pods
docker build -t myapp:v1 .              # build the image (section 6)
oc new-app --image-stream=myapp:v1 --name=myapp
oc create route edge --service=myapp    # public HTTPS URL
oc get route myapp
```

After pushing new code, rebuild and roll out:

```bash
docker build -t myapp:v1 . && oc rollout restart deploy/myapp
```

Permissions cover your namespace only. Commands that need cluster-admin (`oc adm ...`, other namespaces, privileged pods) are refused.

### 8. AI agents: Claude Code and Codex

Both agents are preinstalled and preconfigured to **auto-approve**: they run commands and edit files without asking first. They can't leave the dev box's namespace.

```bash
cd ~/workspace/myproject
claude          # first run: follow the login link (Claude subscription) or set ANTHROPIC_API_KEY
codex login     # then: codex
```

Your logins are saved in `~/.claude` and `~/.codex` and survive restarts. API keys can also be provided by the admin (section 13).

To switch auto-approve off, edit `~/.claude/settings.json` (remove `"defaultMode": "bypassPermissions"`) or `~/.codex/config.toml` (set `approval_policy = "on-request"`). Your changes are kept, because the defaults are copied only once.

> Because the agents act without asking, review their changes with `git diff` before you commit, and keep production credentials out of the dev box.

### 9. Cloud CLIs: gcloud and aws

```bash
gcloud auth login --no-launch-browser     # open the printed link, paste the code back
gcloud config set project <project-id>
gcloud container clusters get-credentials <cluster> --region <region>   # kubectl to GKE

aws configure                             # access key / secret / region
aws sts get-caller-identity
```

Credentials are stored in `~/.config/gcloud` and `~/.aws` on your volume. Prefer short-lived credentials (`aws sso login`, gcloud user login) over long-lived keys.

### 10. Connecting from Antigravity or desktop VS Code (SSH)

You can also work from a desktop editor instead of the browser. The dev box runs an SSH server on port 2222 (key login only).

1. Ask the admin to add your **public** key (`~/.ssh/id_ed25519.pub` on your computer) to the dev box (section 13).
2. On your computer, connect to the cluster and forward the port:
   ```bash
   oc port-forward svc/vscode 2222:2222 -n <namespace>
   ```
3. Add to `~/.ssh/config` on your computer:
   ```
   Host devsuite
     HostName localhost
     Port 2222
     User coder
   ```
4. Test it with `ssh devsuite`, then in **Antigravity** or **VS Code**: Remote-SSH → Connect to Host → `devsuite`.

The first connection installs the editor's server into your home folder. For Antigravity's agent to act without asking, set its terminal-execution and review policies to "Always proceed" in Antigravity's settings on your computer.

Keep the `oc port-forward` command running while you work.

### 11. WireGuard

`wg` and `wg-quick` are installed, so you can generate keys and configs (`wg genkey | tee priv | wg pubkey > pub`). Bringing a tunnel **up** inside the pod needs network-admin rights that OpenShift's default policy doesn't give. That requires a cluster admin and a custom security policy, and isn't possible on Developer Sandbox.

---

## Part B: Deploying and maintaining

### 12. First-time deployment

Requirements: the `oc` CLI, and a user who is admin of the target namespace. That's the default for your own namespace on Developer Sandbox.

```bash
git clone https://github.com/pavant2007/dev-suite.git && cd dev-suite
cp openshift/secret.example.yaml openshift/secret.yaml
# edit openshift/secret.yaml: set password (and optionally ssh-authorized-keys, API keys)

oc login --web https://api.<cluster-domain>:6443     # or oc login --token=...
oc apply -k openshift/ -n <namespace>
oc rollout status deploy/vscode -n <namespace>
oc get route vscode -n <namespace> -o jsonpath='https://{.spec.host}{"\n"}'
```

What gets created:

| Object | Purpose |
|---|---|
| ServiceAccount `vscode` + RoleBinding `vscode-edit` | identity of the dev box; `edit` role in this namespace only (needed for `docker build/run/compose` and `oc`) |
| Secret `vscode-auth` | password, SSH keys, optional API keys |
| PVC `vscode-home` (20 Gi) | `/home/coder` |
| Deployment `vscode` | the dev box (1 replica, non-root) |
| Service + Route `vscode` | HTTPS URL; SSH port 2222 is internal only |

The RoleBinding must be created by a **user** who is namespace admin. A service account usually can't grant roles. If you deploy with a service account and the RoleBinding is refused, apply `rbac.yaml` once as yourself, or point the deployment at an existing service account that already has `edit`:

```bash
oc patch deploy vscode --type=merge -p '{"spec":{"template":{"spec":{"serviceAccountName":"<sa-with-edit>"}}}}'
```

### 13. Changing the password, SSH keys or API keys

Edit `openshift/secret.yaml`, then apply it and restart the pod (it reads the secret at startup):

```bash
oc apply -f openshift/secret.yaml -n <namespace>
oc rollout restart deploy/vscode -n <namespace>
```

Fields in `secret.yaml`:

| Key | Meaning |
|---|---|
| `password` | code-server login password (required) |
| `ssh-authorized-keys` | public SSH keys, one per line; empty disables SSH |
| `anthropic-api-key` | optional, for Claude Code |
| `openai-api-key` | optional, for Codex |

Keep `secret.yaml` out of git (it's already in `.gitignore`).

### 14. Updating to a new image

A new image is published to `ghcr.io/pavant2007/dev-suite:latest` whenever `main` changes. The deployment always pulls the newest image, so updating just means restarting:

```bash
oc rollout restart deploy/vscode -n <namespace>
oc rollout status deploy/vscode -n <namespace>
```

Files in `/home/coder` are kept. To pin a version, set `image:` in `openshift/deployment.yaml` to a `sha-<commit>` or `vX.Y.Z` tag.

### 15. Resources and storage

Defaults in `deployment.yaml`: requests of 0.5 CPU / 2 Gi memory, and limits of 4 CPU / 8 Gi memory. The home volume is 20 Gi. On Developer Sandbox, the namespace quota caps the total, so lower these values if pods don't start (`oc describe quota`).

To grow the home volume (if the storage class allows it):

```bash
oc patch pvc vscode-home -n <namespace> -p '{"spec":{"resources":{"requests":{"storage":"40Gi"}}}}'
```

Images built with `docker build` and apps started with `docker compose` count against the same namespace quota. Remove what you no longer need: `docker compose down`, `docker stop`, `oc delete is <name>`.

### 16. Customizing the image

- **Tool versions:** change the `ARG` values at the top of the [Dockerfile](../Dockerfile) (`MAVEN_VERSION`, `GRADLE_VERSION`, `CODE_SERVER_VERSION`, `KUBECTL_VERSION`, `PYTHON_VERSION`, …).
- **Python libraries:** edit [requirements.txt](../requirements.txt).
- **VS Code extensions:** edit the `EXTENSIONS` list in the Dockerfile. IDs come from [open-vsx.org](https://open-vsx.org).
- **Agent defaults:** edit [agent-defaults/](../agent-defaults/).

Push to `main` (or open a pull request). CI builds and tests the image and, on `main`, publishes it. Then restart the deployment (section 14). Before pushing, make sure no secrets or personal details are in the change.

---

## Part C: Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Browser shows "Application is not available" | The pod isn't running yet, or crashed. Run `oc get pods -l app=vscode`, then `oc logs deploy/vscode`. |
| Login page says the password is wrong | Check the `password` in the secret; after changing it, run `oc rollout restart deploy/vscode`. |
| Terminal stopped responding after an update | The pod restarted. Reload the browser tab and open a new terminal. |
| `docker: no Docker daemon in this pod` | You used a Docker command without an OpenShift equivalent (for example `docker network`). See section 6 for supported commands. |
| `docker build` fails with `forbidden` | The pod's service account lacks build rights. Apply `openshift/rbac.yaml` as a namespace admin (section 12). |
| Pod from `docker run` / `compose` is in `CrashLoopBackOff`, or logs show `permission denied` | The image expects root. Use a non-root variant (section 6 table). |
| Build is stuck in `Pending` / `New` | Namespace build quota is exhausted, or another build is running. Run `oc get builds`, then `oc describe quota`. |
| `docker compose up` warns that a bind mount was ignored | Bind mounts aren't supported. Copy the files into the image with `COPY` in the Dockerfile. |
| Can't reach my app at `localhost:PORT` from my laptop | Use the Route URL (`oc get route`) or `oc port-forward`. For apps started in the dev box terminal, use `https://<dev-box-url>/proxy/PORT/`. |
| `apt install` fails | The dev box isn't root. Use `pip install`, a binary in `~/bin`, or add the tool to the image (section 16). |
| SSH: `Permission denied (publickey)` | Your public key isn't in `ssh-authorized-keys`, or the pod wasn't restarted after the change (section 13). |
| SSH: connection refused | `oc port-forward svc/vscode 2222:2222` isn't running on your computer. |
| Disk full / `No space left on device` | `/home/coder` is full. Clean `~/.m2`, `~/.gradle/caches` and `~/.cache`, or grow the PVC (section 15). |
| Java extension is slow on first open | It's indexing. Wait a minute, or give the pod more memory (section 15). |
| Agent says it isn't logged in | Run `claude` or `codex login` again, or have the admin set the API key (section 13). |
