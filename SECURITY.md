# Security

DnDFox runs JavaScript in Firefox's privileged browser-chrome context through
Autoconfig. This is intentionally more powerful than a WebExtension and can
access internal Firefox APIs and browser UI state.

Only install releases obtained from this repository. Review changes to files
under `src`, `scripts`, and `vendor` before running an untrusted fork.

Do not report Firefox internal-API compatibility problems as security issues.
For an actual vulnerability, use GitHub's private vulnerability reporting for
the repository rather than opening a public issue.
