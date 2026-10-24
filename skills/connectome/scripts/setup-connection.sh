#!/bin/bash
set +x
set +v
set +a
set -eu
export LC_ALL=C

fail() { printf '%s\n' "$1" >&2; exit 1; }
usage='Usage: setup-connection.sh CONFIG_PATH NAME URL [--renew]'
if [[ $# -eq 1 && $1 == --help ]]; then printf '%s\n' "$usage"; exit 0; fi
[[ $# -eq 3 || ( $# -eq 4 && $4 == --renew ) ]] || fail "$usage"
profile=$1
name=$2
endpoint=$3
renew=${4:-}
[[ $name =~ ^[a-z][a-z0-9_]*$ ]] || fail 'Use a connection name containing lowercase letters, digits, and underscores, starting with a letter.'
case "$profile" in
  /*) ;;
  *) fail 'Use an absolute config path outside the shared skill and repository.' ;;
esac
case "$profile/" in */../*|*/./*|*//*) fail 'Use a normalized config file path.' ;; esac
[[ ! $profile =~ [[:cntrl:]] ]] || fail 'The config path contains a control character.'
[[ $endpoint =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]] || fail 'Use an upstream usql URL with a scheme and host.'
[[ ! $endpoint =~ [[:space:][:cntrl:]] && $endpoint != *'#'* ]] || fail 'Use a URL with encoded spaces and no fragment.'
scheme=${endpoint%%://*}
address=${endpoint#*://}
authority=${address%%[/?#]*}
[[ -n $authority && $authority != *'@'* ]] || fail 'The URL must contain a host and no username or password.'
[[ ! $endpoint =~ [\?\&\;]([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Ww][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt])= ]] || fail 'Keep authentication values out of the URL. Enter them only in the private prompt.'
directory=${profile%/*}
[[ -n $directory ]] || directory=/

mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
cursor=$directory
while [[ $cursor != / ]]; do
  [[ ! -L $cursor ]] || fail 'A config directory is a symlink. Choose a private physical directory.'
  cursor=${cursor%/*}
  [[ -n $cursor ]] || cursor=/
done
if [[ -e $directory ]]; then
  [[ -d $directory && -O $directory ]] || fail 'The config directory must belong to the current user.'
  permissions=$(mode "$directory")
  (( (8#$permissions & 077) == 0 )) || fail 'The config directory must have owner-only permissions. Existing permissions were not changed.'
else
  cursor=$directory
  while [[ ! -e $cursor ]]; do cursor=${cursor%/*}; [[ -n $cursor ]] || cursor=/; done
  [[ -d $cursor && -O $cursor ]] || fail 'Create the config directory inside a directory owned by the current user.'
  permissions=$(mode "$cursor")
  (( (8#$permissions & 022) == 0 )) || fail 'The existing parent directory is writable by other users. Choose a private location.'
fi
[[ ! -L $profile ]] || fail 'The config file is a symlink. It was not changed.'
previous=
if [[ -e $profile ]]; then
  [[ -f $profile && -O $profile ]] || fail 'The existing config must be a regular file owned by the current user.'
  permissions=$(mode "$profile")
  (( (8#$permissions & 077) == 0 )) || fail 'The existing config must have owner-only permissions. It was not changed.'
  if [[ -z $renew ]]; then
    printf '%s\n' 'Existing profile kept. Verify the named connection with usql.'
    exit 0
  fi
  previous=$(cksum < "$profile")
  line_count=0
  entry=
  header=
  while IFS= read -r line || [[ -n $line ]]; do
    line_count=$((line_count + 1))
    case $line_count in 1) header=$line ;; 2) entry=$line ;; *) break ;; esac
  done < "$profile"
  pattern="^  $name: '([^']|'')*'$"
  [[ $line_count -eq 2 && $header == connections: && $entry =~ $pattern ]] || fail 'Renewal refused. The existing file is not the single-connection form created by this helper.'
  unset line entry header
  [[ $(cksum < "$profile") == "$previous" ]] || fail 'The existing profile changed. Retry setup.'
fi

[[ -t 0 && -t 1 && -t 2 ]] || fail 'A private, user-visible local terminal is required. Do not send credentials through chat or a pipe.'
if ! { exec 3<>/dev/tty; } 2>/dev/null; then fail 'No controlling terminal is available for private input.'; fi
command -v link >/dev/null || fail 'The native link utility is required for safe profile creation.'
temporary=
terminal_state=$(stty -g <&3)
cleanup() {
  stty "$terminal_state" <&3 2>/dev/null || :
  [[ -z $temporary ]] || rm -f -- "$temporary"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM
unset username password encoded_username encoded_password REPLY dsn
stty -echo <&3
printf '%s' 'Username: ' >&3
IFS= read -r username <&3 || fail 'Input cancelled. The profile was not changed.'
printf '\n%s' 'Password: ' >&3
IFS= read -r password <&3 || fail 'Input cancelled. The profile was not changed.'
printf '\n' >&3
stty "$terminal_state" <&3
[[ -n $username && -n $password ]] || fail 'Empty input cancelled setup. The profile was not changed.'
url_encode() {
  local value=$1 encoded= character index
  for ((index=0; index<${#value}; index++)); do
    printf -v character '%%%02X' "'${value:index:1}"
    encoded=$encoded$character
  done
  REPLY=$encoded
}
url_encode "$username"
encoded_username=$REPLY
url_encode "$password"
encoded_password=$REPLY
dsn="$scheme://$encoded_username:$encoded_password@$address"
dsn=${dsn//\'/\'\'}
umask 077
mkdir -p -- "$directory"
[[ -d $directory && ! -L $directory && -O $directory ]] || fail 'The config directory changed during input. Retry setup.'
permissions=$(mode "$directory")
(( (8#$permissions & 077) == 0 )) || fail 'The config directory is no longer private. The profile was not changed.'
temporary=$(mktemp "$directory/.setup-XXXXXXXX")
chmod 600 "$temporary"
printf "connections:\n  %s: '%s'\n" "$name" "$dsn" > "$temporary"
unset username password encoded_username encoded_password REPLY dsn
if [[ -n $previous ]]; then
  [[ -f $profile && ! -L $profile && -O $profile ]] || fail 'The existing profile changed during input. Retry setup.'
  [[ $(cksum < "$profile") == "$previous" ]] || fail 'The existing profile changed during input. It was not overwritten.'
  mv -f -- "$temporary" "$profile"
else
  link "$temporary" "$profile" 2>/dev/null || fail 'A profile already exists or could not be published. It was not overwritten.'
fi
printf '%s\n' 'Saved the local profile. Verify the named connection with usql.'
