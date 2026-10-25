# Local installation preference

Keep exactly one launchable AgentDeck: the latest verified version at `/Applications/AgentDeck.app`.

- After installing and validating, move every duplicate `.app` to Trash: Debug/Release build products, temporary copies, old backups. Keep no rollback bundles anywhere.
- `make install` cleans the build directory; `make run` opens the installed app. After other build/test runs, use `make cleanup-installs` once the latest version is installed and verified.
- Never remove source code, `~/Library/Application Support/AgentDeck` or browser profiles.
- Increment the patch version once per deployment, per the deployment-versioning skill.
