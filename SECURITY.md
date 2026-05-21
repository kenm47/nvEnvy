# Security

If you discover a security issue in nvEnvy, please report it privately rather
than opening a public issue. You can:

- Use GitHub's private security advisory flow:
  <https://github.com/kenm47/nvEnvy/security/advisories/new>
- Or email the maintainer directly (see the commit author on recent commits
  for the address).

Please include a clear description of the issue, steps to reproduce, and the
nvEnvy version (Mac App Store build or direct-download build) you tested
against.

Best-effort response time is a few days. There is no bounty program.

## Scope

In scope:

- The shipped nvEnvy.app binary (both the direct-download and Mac App Store
  variants).
- The `NvEnvyCore` Swift package.

Out of scope:

- Vulnerabilities in upstream dependencies (Sparkle, KeyboardShortcuts, Yams,
  swift-markdown) — please report those to the respective projects.
- Vulnerabilities in macOS itself or in iCloud Drive — report to Apple via
  <https://security.apple.com/>.
