param($arq)
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $arq),[ref]$null,[ref]$null)
$def=@{}; $ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | % { $def[$_.Name]=1 }
$ast.FindAll({$args[0] -is [System.Management.Automation.Language.CommandAst]},$true) | % { $_.GetCommandName() } | ? { $_ -and $_ -match '^[A-Za-z]+-[A-Za-z]' } | Sort-Object -Unique | ? { -not $def.ContainsKey($_) -and -not (Get-Command $_ -CommandType Cmdlet,Function,Alias -ErrorAction SilentlyContinue) } | ? { $_ -notin 'Get-CimInstance','Get-WmiObject' } | % { "FUNCAO INEXISTENTE: $_" }
