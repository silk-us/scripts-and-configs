# Claude Code Rules

## Git

**NEVER push directly to main.** No exceptions. Every change must go through a branch and PR.

- Always create a new branch before committing
- Push to the branch, not main
- Open a PR via `gh pr create`
- Do NOT run `git push origin main` under any circumstances

## Commit messages and PRs

No AI attribution, co-author signatures, or "Generated with" footers in commit
messages, PR titles, or PR bodies. Describe what changed and why, nothing else.

## PowerShell

- Target Windows PowerShell 5.1 unless a script states otherwise. It is what
  ships with Windows Server and what SQL Server Agent launches.
- ASCII only. No em-dashes, en-dashes or smart quotes: they corrupt scripts
  delivered through Azure Run Command and other remote execution paths.
- Scripts here are handed to customers. Prefer no external module dependencies
  where the built-in cmdlets can do the job.
