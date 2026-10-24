# Establish the current user's access

The agent handles client setup, paths, and connection checks. The analyst supplies credentials once in a private local prompt. Each teammate uses their own access.

## Inspect the host and reuse working access

1. Identify the actual desktop host, shell, persistent local storage, and available user-visible terminal. Check the source's network and VPN requirements.
2. Run `usql --version`. If the client is missing, install only upstream usql through an authorized host installation route. Use the [upstream installation and driver documentation](https://github.com/xo/usql/tree/v0.21.6#installing). Confirm that the installed build supports the source.
3. Reuse a known, valid native usql connection or an existing upstream authentication flow. Run the source's small read-only connection check in a new usql process. A working default named connection needs no helper or separate config.
4. If a connection fails, distinguish missing client or driver support, network or VPN failure, TLS or policy failure, permission denial, and expired authentication. Request fresh credentials only when evidence identifies an authentication change or expiry.

Never print a live config, a credential-bearing URL, or `\cset` output. Use `-X` to suppress startup scripts and `-w` to prevent an unexpected password prompt in agent execution. Authentication methods other than username and password remain upstream-owned. These helpers are an optional convenience for ordinary URL userinfo authentication, not an adapter for every auth method.

## Prepare one local password prompt

Prepare the logical name, the full upstream URL with no credentials, and an absolute config path. The URL may contain nonsecret source options, including required TLS settings. It must contain no username, password, token, or other secret anywhere, including query parameters. The helpers reject userinfo and common secret options, but cannot identify every possible secret in an arbitrary option.

Use a name matching `[a-z][a-z0-9_]*`. Prefer `~/.connectome/connections/<name>.yaml` on Unix and the same directory under the actual Windows user profile. Confirm that this location is persistent and outside shared, synced, skill, and repository folders. Select a different private local location if the home directory is shared or synced. Pass the exact path to both the helper and usql. Do not set a global `USQL_CONFIG` variable.

Explain the storage choice before the prompt. The native file contains a plaintext password protected by owner-only filesystem access. Software running as the same user, an administrator, or a backup system with access can read it. No credential service or extra encryption is added.

Open the prepared command in an actual user-visible local terminal when the host supports it. Otherwise, give the analyst the fully prepared nonsecret command and help them run it in their own terminal. Explain that they will enter their database username and password there once, and the saved connection stays on that computer. The agent prepares the paths and command; the analyst supplies only the credentials.

Use Bash on macOS or Linux, or built-in Windows PowerShell 5.1 in a console. A captured agent PTY is not evidence that the analyst can see or privately use it. Never collect credentials through chat, tool input, command arguments, environment variables, or a pipe. The helpers prompt for both fields without displaying their values. Empty input or cancellation leaves the existing profile intact.

If no private user-visible input channel is available, stop credential setup and name that blocker. Preserve the source work. Do not request a password in chat or substitute an agent-only terminal. If Windows execution policy blocks the script, report that policy blocker. Do not change policy or use a bypass flag.

The following examples are for the agent to complete before launch. Replace the URL placeholder with the source's nonsecret upstream URL. Run from the skill directory, or use an absolute helper path.

```bash
connectome_config="$HOME/.connectome/connections/source_name.yaml"
connectome_url='DRIVER://HOST/DATABASE?NONSECRET_OPTIONS'
/bin/bash ./scripts/setup-connection.sh "$connectome_config" source_name "$connectome_url"
```

```powershell
$connectomeConfig = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.connectome\connections\source_name.yaml'
$connectomeUrl = 'DRIVER://HOST/DATABASE?NONSECRET_OPTIONS'
.\scripts\setup-connection.ps1 -ConfigPath $connectomeConfig -Name source_name -Url $connectomeUrl
```

The [Bash helper](../scripts/setup-connection.sh) and [PowerShell helper](../scripts/setup-connection.ps1) write one named connection in one native YAML file. They create private directories without changing permissions on existing shared directories. Existing directories and files must already have safe ownership and permissions. They refuse symlinks or reparse paths. Correct an unsafe location through the host's authorized filesystem controls, or choose a new private location.

The saved value is a URI string with percent-encoded username and password. This representation preserves spaces and punctuation in usql v0.21.6. Its map-form credential builder changes spaces to plus signs, as shown in the [upstream URL builder](https://github.com/xo/dburl/blob/v0.25.1/dburl.go#L409-L433). The helper owns no driver, query, or authentication implementation.

## Verify and use the saved connection directly

After setup, run an independent connection check through usql. Prepare a small read-only query in the source's dialect that confirms the intended database or view; substitute its actual file path below. A successful file save alone does not prove access.

```bash
usql -X -w --config "$connectome_config" source_name -f ./queries/connection-check.sql
```

```powershell
usql -X -w --config $connectomeConfig source_name -f .\queries\connection-check.sql
```

Use the same explicit config path and logical name for later direct usql calls. For a previously working default named connection, omit `--config`. An alternate config does not merge the default config's settings. Record any required nonsecret options or session conventions in the source setup guidance. See [native usql configuration](https://github.com/xo/usql/tree/v0.21.6#configuration).

An ordinary helper rerun preserves the existing file without prompting. It does not certify that the file contains a working connection. Verify with usql. For a confirmed credential change or expiry, rerun the same helper with `--renew` on Bash or `-Renew` on PowerShell. Renewal accepts only the helper's two-line single-connection form. It refuses unfamiliar YAML, additional connections, and changes detected during input. Preserve those files and choose a separate profile instead of forcing replacement.

Run one renewal for a given profile at a time. Creation cannot overwrite another creator's file. Renewal checks for intervening edits before atomic replacement but does not serialize simultaneous renewals. Cancellation and failed input preserve the previous file. No helper runs SQL or verifies that a newly entered password is correct.

## Package independent setup for teammates

Give a generated source skill its own nonsecret source locator, prerequisites, logical name, chosen per-user path convention, direct usql command, source-specific connection check, and renewal instruction. Include the standalone helper for each needed host in its `scripts/` directory. Do not make teammates depend on the factory's installed files. Keep credentials and local config outside the distributed skill. Do not copy this entire factory guide when a shorter source-specific setup page is sufficient.

The helpers target Bash 3-compatible macOS and Linux environments and built-in Windows PowerShell 5.1. The core PTY tests pass on Ubuntu and macOS, including hidden input, Unicode preservation, permissions, reuse, renewal, and cancellation. Linux has also been exercised with usql v0.21.6 and authenticated read-only access to a local copy of Wide World Importers. Windows interactive input and ACL behavior, and a real analyst's desktop prompt, remain unverified. Upstream driver and authentication support remains the compatibility boundary.
