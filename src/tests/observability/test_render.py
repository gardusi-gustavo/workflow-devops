import json
import tempfile
import unittest
from pathlib import Path

from observability.render import load, render


class RenderTest(unittest.TestCase):
    def test_renders_latest_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "2026" / "11.jsonl"
            path.parent.mkdir(parents=True)
            rows = [
                {"v": 1, "day": "2026-11-05", "scope": "service:gitea", "metric": "gitea_repositories", "value": 28},
                {"v": 1, "day": "2026-11-06", "scope": "service:gitea", "metric": "gitea_repositories", "value": 31},
                {"v": 1, "day": "2026-11-06", "scope": "repo:templates/md", "metric": "repo_open_issues", "value": 0},
                {"v": 1, "day": "2026-11-06", "scope": "repo:templates/md", "metric": "repo_size_bytes", "value": 2048},
            ]
            path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
            page = render(load(root))
            self.assertIn("`2026-11-06`", page)
            self.assertIn("| Repositories | 31 |", page)
            self.assertIn("| templates/md | 0 |", page)
            self.assertIn("2.0 KB", page)


if __name__ == "__main__":
    unittest.main()
