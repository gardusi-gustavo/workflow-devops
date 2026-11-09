# 📟 On-call

**What this is:** the duties, severity model, and handoff for the private stack.

## Rotation

| Role | Owner |
| --- | --- |
| Primary | `human` |
| Secondary | `bot-event` |
| Handoff | Monday, written summary |

This is a single-operator setup. The rotation is a checklist, not a 24/7 staffed
rota.

## Duties

- acknowledge alerts
- triage and assign follow-up issues
- keep an incident timeline
- verify the microSD backup and the restore path
- check disk, TLS, and the static telemetry page
- review capacity monthly
- write a postmortem for P1/P2
- keep runbooks current
- review config and deployment drift
- maintain alert ownership

## Severity

See [severity.md](severity.md).

## Escalation

See [escalation.md](escalation.md).

## Handoff

See [handoff.md](handoff.md).

## SLOs

See [slo.md](slo.md).

## Runbooks

- [Gitea](runbooks/gitea.md)
- [Runner](runbooks/runner.md)
- [Static telemetry](runbooks/telemetry.md)
- [Backup](runbooks/backup.md)
- [Disk](runbooks/disk.md)
- [TLS](runbooks/tls.md)

## Incidents and postmortems

- [Incident template](incidents/_template.md)
- [Postmortem template](postmortems/_template.md)

## Known problems

See [known-problems.md](known-problems.md).

## Deferred work

See [deferred.md](deferred.md).

## Recovery

See [recovery.md](recovery.md).
