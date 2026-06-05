# Contributing

## Commit Message Format

```
<type>: <short summary>
  - <detail 1>
  - <detail 2>
```

Types: `feat` `fix` `hw` `doc` `refac` `test` `wip`

## Workflow

```bash
git switch main
git pull --rebase
git switch -c feat/my-change
# develop...
git add -A
git commit -m "hw: add systolic array pe module"
git push -u origin feat/my-change
# Open PR on GitHub
# After review: merge via GitHub or locally
```

## Before Pushing

1. Review what you changed: `git diff origin/main --stat`
2. Review line-by-line: `git diff origin/main`
3. Run tests / simulation
4. Commit with clear message
5. Push

## Code Review

- Every non-trivial change should go through a PR review
- Keep PRs small and focused on one thing
- Review for: correctness, style, test coverage, I/O efficiency
