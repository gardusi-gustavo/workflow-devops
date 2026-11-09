# 🔁 Improve a repo

**What this is:** a loop that shrinks a repo toward its core — audit, minimize, remove, and let the checks hold the line.

## 🔎 Audit

- **Wrapper scan** — find every external process the code starts (`os/exec`, `subprocess`, shells). Each one is a dependency to justify or remove.
- **Dependency check** — what the build and the image pull in; what the runtime needs.
- **Unused-path check** — unreferenced files, stale scripts, duplicated logic.

## 🧼 Minimize

- Keep one concern per repo.
- Prefer a **library** over a wrapper: logic that compiles in beats logic that shells out.
- Keep the image minimal — only what the binary needs.

## 🗑️ Remove

Delete unused paths and wrappers, then close the issue that tracked them.

## 🧪 Feedback loop

- **Validators fail closed** — structure, content, links, records.
- **Coverage gates** — generated numbers must match the live tree.
- **Smoke tests** — the image and the binary run the core path.

## ♾️ Infinite pursuit

A repo is never finished. Take a pass, add the validator that closes the gap you found, and repeat. See [../issues/](../issues/).

## 🔗 Related

- [../issues/](../issues/) — issue and question records
- [../README.md](../README.md) — repository docs index
