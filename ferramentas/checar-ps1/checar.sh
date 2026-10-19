#!/bin/bash
D=$(dirname "$0")
for f in "$@"; do
  echo "== $f"
  pwsh -NoProfile -Command "\$e=\$null;[void][System.Management.Automation.Language.Parser]::ParseFile('$f',[ref]\$null,[ref]\$e); if(\$e){\$e|%{'PARSE: '+\$_.Message}}"
  for c in esc funcs sombra caixa; do pwsh -NoProfile -File $D/$c.ps1 "$f"; done
done
