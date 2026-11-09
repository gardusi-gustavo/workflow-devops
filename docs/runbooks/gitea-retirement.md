# Gitea retirement runbook

Gitea is retired only after the GitHub mirrors and restore drill pass.

## Checklist

1. Export open issues and pull-request metadata to `gardusi-gustavo/private`.
2. Verify every `gardusi-gustavo/*` mirror has the expected default branch.
3. Run `infra/scripts/github/pre-publication-audit.sh` with `critical=0`.
4. Run a bundle restore drill from the latest backup.
5. Confirm PyPI, npm, crates, Docker Hub, Pages, and the GitHub App.
6. Freeze the Gitea service.
7. Keep the final bundle and `SHA256SUMS` for three retention cycles.
8. Update local clones to the GitHub remotes.

## Rollback

If a mirror is incomplete, keep Gitea read-only and restore from the bundle.
Do not delete the final Gitea backup until the restore drill passes.
