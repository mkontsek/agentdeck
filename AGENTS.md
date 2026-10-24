# Local installation preference

- Keep exactly one launchable AgentDeck installation: the latest verified version at `/Applications/AgentDeck.app`.
- After installation and validation, move duplicate `.app` bundles to Trash, including Debug/Release build products, temporary copies, and old installation backups. Do not retain rollback `.app` bundles in the repository or elsewhere.
- `make install` performs build-directory cleanup; `make run` opens the installed app. After other build/test workflows, use `make cleanup-installs` once the latest version is installed and verified.
- Preserve source code, `~/Library/Application Support/AgentDeck`, and browser profiles when removing application copies.
- Increment the patch version once per new deployment, following the deployment-versioning skill.
