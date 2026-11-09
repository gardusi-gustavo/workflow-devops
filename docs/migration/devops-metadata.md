# devops metadata export

**What this is:** the pre-retirement export of native Gitea metadata for the
former `devops` repository.

The export lives outside Git on the backup host:

```text
/srv/backup/gitea-metadata/devops/20261109T224214Z/
```

Counts:

| Record | Count |
| --- | --- |
| Labels | 37 |
| Milestones | 5 |
| Issues | 98 |
| Pull requests | 196 |
| Releases | 6 |
| Git tags | 57 |
| Issue comments | 105 |
| PR conversation comments | 50 |
| PR reviews | 180 |
| PR review comments | 0 |
| Attachments | 0 |

The directory contains JSON records, `manifest.json`, and `SHA256SUMS`. The
export is not a substitute for the weekly full Gitea dump; it is the portable
copy that can be reviewed without Gitea. The full dump remains until the wider
metadata export is complete.
