param([string]$ConfigPath, [string]$Name, [string]$Url, [switch]$Renew)

Set-PSDebug -Off
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$temporary = $null
$failure = 'Setup could not complete. Check the local profile path and permissions before retrying.'

function Stop-Setup([string]$Message) {
    $script:failure = $Message
    throw 'Setup stopped.'
}

function Assert-Private([string]$Path, [bool]$Directory) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.PSIsContainer -ne $Directory) {
        Stop-Setup 'The config must use a regular file and directory, without reparse points.'
    }
    $acl = Get-Acl -LiteralPath $Path
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $owner.Value) {
        Stop-Setup 'The config file and directory must belong to the current user.'
    }
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -ne $owner.Value) {
            Stop-Setup 'The existing config file and directory must have owner-only access. Existing permissions were not changed.'
        }
    }
}

function Read-Private([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        if ($secure.Length -eq 0) { Stop-Setup 'Empty input cancelled setup. The profile was not changed.' }
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [Uri]::EscapeDataString([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer))
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $secure.Dispose()
    }
}

try {
    if ($PSVersionTable.PSVersion -lt [version]'5.1' -or $PSVersionTable.PSEdition -ne 'Desktop') {
        Stop-Setup 'Use built-in Windows PowerShell 5.1 in a local console. Do not bypass execution policy.'
    }
    if (-not $ConfigPath -or -not $Name -or -not $Url -or $args.Count -ne 0) {
        Stop-Setup 'Usage: setup-connection.ps1 CONFIG_PATH NAME URL [-Renew]'
    }
    if ($Name -cnotmatch '^[a-z][a-z0-9_]*$') {
        Stop-Setup 'Use a connection name containing lowercase letters, digits, and underscores, starting with a letter.'
    }
    if ($ConfigPath -notmatch '^[A-Za-z]:[\\/]' -or $ConfigPath -match '[\x00-\x1f]') {
        Stop-Setup 'Use an absolute local config path outside the shared skill and repository.'
    }
    $endpointMatch = [regex]::Match($Url, '^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+)([^#]*)$')
    if (-not $endpointMatch.Success -or $Url -match '[\s\x00-\x1f]') {
        Stop-Setup 'Use an upstream usql URL with a scheme, host, encoded spaces, and no fragment.'
    }
    $scheme = $endpointMatch.Groups[1].Value
    $address = $Url.Substring($scheme.Length + 3)
    if (($address -split '[/?]', 2)[0].Contains('@') -or $Url -match '[?&;](password|pwd|token|secret)=') {
        Stop-Setup 'The URL must contain no authentication values. Enter them only in the private prompt.'
    }
    $ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
    $directory = [IO.Path]::GetDirectoryName($ConfigPath)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $cursor = $directory
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Stop-Setup 'A config directory is a reparse point. Choose a private physical directory.'
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    if (Test-Path -LiteralPath $directory) {
        Assert-Private $directory $true
    }
    else {
        $cursor = [IO.Path]::GetDirectoryName($directory)
        while (-not (Test-Path -LiteralPath $cursor)) { $cursor = [IO.Path]::GetDirectoryName($cursor) }
        $acl = Get-Acl -LiteralPath $cursor
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $owner.Value) {
            Stop-Setup 'Create the config directory inside a directory owned by the current user.'
        }
        $writeRights = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @($owner.Value, 'S-1-5-18', 'S-1-5-32-544') -and ($rule.FileSystemRights -band $writeRights) -ne 0) {
                Stop-Setup 'The existing parent directory is writable by other users. Choose a private location.'
            }
        }
    }
    $previous = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        Assert-Private $ConfigPath $false
        if (-not $Renew) { Write-Output 'Existing profile kept. Verify the named connection with usql.'; exit 0 }
        $bytes = [IO.File]::ReadAllBytes($ConfigPath)
        if ([Text.Encoding]::UTF8.GetString($bytes) -cnotmatch ("\Aconnections:\n  " + $Name + ": '(?:[^'\r\n]|'')*'\n\z")) {
            Stop-Setup 'Renewal refused. The existing file is not the single-connection form created by this helper.'
        }
        $previous = [Convert]::ToBase64String($bytes)
        $bytes = $null
    }
    if (-not [Environment]::UserInteractive -or $Host.Name -ne 'ConsoleHost' -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) {
        Stop-Setup 'A private, user-visible local console is required. Do not send credentials through chat or a pipe.'
    }
    $username = Read-Private 'Username'
    $password = Read-Private 'Password'
    $dsn = ($scheme + '://' + $username + ':' + $password + '@' + $address).Replace("'", "''")
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetOwner($owner)
    $security.SetAccessRuleProtection($true, $false)
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
    [IO.Directory]::CreateDirectory($directory, $security) | Out-Null
    Assert-Private $directory $true
    $temporary = Join-Path $directory ('.setup-' + [Guid]::NewGuid().ToString('N'))
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $content = [Text.Encoding]::UTF8.GetBytes("connections:`n  ${Name}: '$dsn'`n")
        $stream.Write($content, 0, $content.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    $username = $password = $dsn = $content = $null
    Assert-Private $temporary $false
    if ($null -ne $previous) {
        Assert-Private $ConfigPath $false
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ConfigPath)) -cne $previous) {
            Stop-Setup 'The existing profile changed during input. It was not overwritten.'
        }
        [IO.File]::Replace($temporary, $ConfigPath, $null)
    }
    else { [IO.File]::Move($temporary, $ConfigPath) }
    Write-Output 'Saved the local profile. Verify the named connection with usql.'
}
catch { [Console]::Error.WriteLine($failure); exit 1 }
finally {
    if ($temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
}
