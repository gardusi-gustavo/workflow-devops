# 🤖 Agent runtime

**What this is:** the account and capability contract for the single human
Linux login `user`, Gitea human `human`, bot OS account `gitea-automation`, Gitea bot `bot-event`, and the
rootless Gitea runner.

## Accounts

| Capability | `user` (Gitea `human`) | `bot-event` (Gitea bot) | `gitea-runner` (service) |
| --- | --- | --- | --- |
| OS account | yes, UID 1001 | no | yes, UID 1500 |
| sudo | yes | no | no |
| OpenCode | yes | no | no |
| Chrome | yes | no | no |
| Rootless Docker | no | no | yes |
| Rootful Docker socket | only `sudo docker` | no | no |
| Gitea admin | yes | no | no |
| Gitea approve/merge | yes | no | no |
| Gitea PR author | no | yes (token/SSH) | no |
| `/srv/backup` | yes | no | no |
| `/srv/observability` | yes | no | no |

`user` is the only human login account (Gitea `human`). The bot is a Gitea identity
with its own token and SSH key; it has no Linux account and no home directory.

`gitea-runner` is a system account used only by the Gitea runner. It has no sudo,
no desktop session, and no access to the human home or Gitea data.

## Groups

- `opencode` — execute the shared `/usr/local/lib/opencode` binary.
- `chrome` — execute the shared Chrome binary.
- `media` — write the microSD card.
- `users`, `cdrom`, `plugdev`, `lpadmin` — normal desktop access.

Sharing the Chrome **binary** is fine. Do not share a Chrome profile between
identities: cookies, sessions, and Gitea approvals must stay separate.

## Docker

Production containers (`gitea`, observability) run on the rootful daemon and are
managed by `user` with `sudo docker`.

The only rootless daemon is the CI runner:

```text
gitea-runner  unix:///run/user/1500/docker.sock
```

Do not add `user` to the `docker` group. The group controls the
rootful daemon and is equivalent to root.

## Runner

The Gitea runner runs under the dedicated `gitea-runner` account.

```text
user:    gitea-runner (uid 1500)
home:    /srv/ci/runner
config:  /srv/ci/runner/runner/config.yml
data:    /srv/ci/runner/runner/data
socket:  unix:///run/user/1500/docker.sock
```

The runner uses rootless Docker to create job containers. Jobs run inside the
prebuilt `ci-universal` image and receive no Docker socket.

`gitea-runner` has no access to:

- `/home/user`
- `/srv/gitea`
- `/srv/backup`

Verified from a disposable container:

```text
/home/user: Permission denied
/srv/gitea: Permission denied
```

The runner config maps `gitea` and `gitea.localhost` to the host bridge at
`172.18.0.1`.

Install or update:

```bash
export DOCKER_HOST=unix:///run/user/1500/docker.sock
./infra/scripts/runner/install.sh
```
