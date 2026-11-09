# Registry provisioning

## PyPI

- Distribution: `gardusi-gustavo-python`
- Configure Trusted Publishing for `gardusi-gustavo/package-python`
- Environment: `pypi`
- No long-lived token is stored.

## npm

- Scope: `@gardusi-gustavo`
- Package: `@gardusi-gustavo/ts`
- Configure provenance and an `NPM_TOKEN` only if OIDC is unavailable.

## crates.io

- Crate: `gardusi-gustavo-rs`
- Store `CARGO_REGISTRY_TOKEN` in the `crates` environment.
- Publish only after the repository exists.

## Docker Hub

- Namespace: `gardusi-gustavo`
- Store `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` in `dockerhub`.
- GHCR is a cache, not a public artifact.

## Rule

Reserve names only when the repository is real. Do not reserve `package-ts` or
`package-rs` before those packages exist.
