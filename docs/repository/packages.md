# Package repositories

**What this is:** the identity and scope ledger for the `templates`
organization.

## Identity

One account owns every registry:

```text
gardusi-gustavo
```

Library packages use the `gardusi-gustavo-kit` family. Docker uses the namespace
directly.

| Repository | Registry | Package | Import or consume |
| --- | --- | --- | --- |
| `ts` | npm | `@gardusi-gustavo/kit` | `import { ... } from "@gardusi-gustavo/kit"` |
| `py` | PyPI | `gardusi-gustavo-kit` | `from gardusi_gustavo_kit import ...` |
| `rs` | crates.io | `gardusi-gustavo-kit` | `use gardusi_gustavo_kit::...` |
| `cs` | NuGet | `Gardusi.Gustavo.Kit` | `using Gardusi.Gustavo.Kit;` |
| `go` | Go proxy | `github.com/gardusi-gustavo/kit` | `import "github.com/gardusi-gustavo/kit"` |
| `java` | Maven Central | `io.github.gardusi.gustavo:kit` | `import io.github.gardusi.gustavo.kit...` |
| `rb` | RubyGems | `gardusi-gustavo-kit` | `require "gardusi-gustavo/kit"` |
| `php` | Packagist | `gardusi-gustavo/kit` | `use Gardusi\Gustavo\Kit\...;` |
| `docker` | Docker Hub | `gardusi-gustavo/<role>` | `FROM gardusi-gustavo/python:0.1.0` |

If `gardusi-gustavo` is unavailable on a registry, use one fallback identity for that
registry and record it in `#168`. Do not switch identity per language.

## Shared package repositories

| Repository | Role |
| --- | --- |
| `sh` | Versioned shell scripts and the `sb` runner |
| `json` | Repository and coverage schemas |
| `md` | AGENTS blocks, issue templates, and repository scaffold |
| `docker` | Shared runtime and CI images |
| `yml` | CI/ingest/release workflows and issue configuration |
| `git` | Git dotfiles and config standards |
| `html` | Shared HTML layouts and components |
| `css` | Shared CSS reset, tokens, and utilities |

These repos are not language libraries. They are consumed by tag-pinned
checkout or raw file URLs, and they do not publish to a language registry.

## Scope

`0.1.0` ships one narrow capability that matches the language's strength:

| Package | Type | 0.1.0 focus | Out of scope |
| --- | --- | --- | --- |
| Python | Water | async fetch, extract, normalize, retry | UI, web framework, data science |
| TypeScript | Electric | DOM/UI state and browser or Node utilities | crawling, server backend |
| Rust | Steel | WebAssembly-friendly deterministic utilities | web services, UI |
| C# | Normal | desktop and Unity-adjacent .NET utilities | ASP.NET by default |
| Go | Fighting | CLI, HTTP, and concurrency plumbing | UI, crawling |
| Java | Psychic | one JVM client or tooling direction | Android, Spring unless chosen |
| Ruby | Fairy | Markdown, text, and Rake tasks | Rails by default |
| PHP | Grass | request, HTML, and configuration helpers | crawling, framework |
| Docker | Ditto | runtime images that transform into another repository's runtime | application images |

The type is a mnemonic, not a contract. The scope hypothesis is investigated in
each repository's `1.98` issue before implementation.

## Reservation and publication

- `#168` is the reservation ledger: account, namespace, 2FA, name availability,
  public hosting path, and blockers.
- Each repository's `1.98` issue publishes `0.1.0` and records the artifact URL.
- Each repository's `AGENTS.md` records its exact identity, scope, and smoke test.
- Go and Packagist require publicly reachable module and VCS paths before they
  can publish.
