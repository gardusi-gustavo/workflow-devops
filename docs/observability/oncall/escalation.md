# 📣 Escalation

## Order

1. Primary: `human`
2. Secondary: `bot-event`
3. Host recovery: `root` on the local machine

## When to escalate

- Gitea or the runner is down for more than 15 minutes.
- The backup cannot be verified or restored.
- A secret is exposed.
- Disk is below 10%.
- A P1 has no clear owner after 15 minutes.

## Channels

- Gitea issue in `gardusi-gustavo/workflow-devops`
- `gardusi-gustavo/workflow-devops` issue for backup or release problems
- `private/records` for credential or account recovery

Do not put secrets in an issue, chat, or commit.
