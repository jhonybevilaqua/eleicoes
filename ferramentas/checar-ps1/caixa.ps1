param($arq)
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $arq),[ref]$null,[ref]$null)
$fns=$ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)
function Dentro($n){ foreach($f in $fns){ if($n.Extent.StartOffset -ge $f.Extent.StartOffset -and $n.Extent.EndOffset -le $f.Extent.EndOffset){return $true} }; $false }
$g=@{}
$ast.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % {
  $p=$_.VariablePath.UserPath
  if($p -notlike 'script:*' -and (Dentro $_)){return}
  $n=$p -replace '^script:',''
  if($n -match ':'){return}
  $k=$n.ToLower(); if(-not $g.ContainsKey($k)){$g[$k]=New-Object System.Collections.Generic.HashSet[string]}; [void]$g[$k].Add($n) }
$g.GetEnumerator() | ? { $_.Value.Count -gt 1 } | % { "MESMA VARIAVEL NO SCRIPT: " + (($_.Value) -join ' / ') }
