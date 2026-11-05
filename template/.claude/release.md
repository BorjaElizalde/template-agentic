# Release facts

The release skill reads this file before it promotes. Keep it to what CI and the deploy do.

## Checks on each promotion PR

- `develop` → `staging`: which checks this PR carries, and what they prove.
- `staging` → `main`: which checks this PR carries, and what they prove.

## A promotion PR with no check

Whether a leg may carry no check at all. If none may, a missing check is a red.

## Deploy

The workflow to wait for after the last merge and how long it can run, or "none".
