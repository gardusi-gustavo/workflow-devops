# TLS and endpoints

## What it is

Local HTTP endpoints and certificates for Gitea and observability.

## Dashboards

- Grafana `Gitea overview`
- Prometheus targets

## Alerts

- `GiteaDown`
- future `TlsExpiringSoon`
- future `EndpointDown`

## Failure modes

- expired certificate
- wrong hostname
- reverse proxy misconfiguration
- local port collision

## Recovery

```sh
curl -vk https://<host>/
openssl s_client -connect <host>:443 -servername <host>
```

Check the Gitea `ROOT_URL`, certificate files, and proxy config.

## Verification

- certificate chain valid
- expiry above 30 days
- endpoint returns expected status
- login and clone work

## Escalation

`human`, then `root`.
