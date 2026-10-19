param($arq)
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $arq),[ref]$null,[ref]$null)
$fns=$ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)
function Dentro($n){ foreach($f in $fns){ if($n.Extent.StartOffset -ge $f.Extent.StartOffset -and $n.Extent.EndOffset -le $f.Extent.EndOffset){return $true} }; $false }
$topo=@{}
$ast.FindAll({$args[0] -is [System.Management.Automation.Language.AssignmentStatementAst]},$true) | ? { -not (Dentro $_) } | % {
  $_.Left.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $n=$_.VariablePath.UserPath; if($n -notmatch ':'){ $topo[$n]=1 } } }
foreach($f in $fns){
  $loc=@{}
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.AssignmentStatementAst]},$true) | % { $_.Left.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $loc[$_.VariablePath.UserPath]=1 } }
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.ForEachStatementAst]},$true) | % { $loc[$_.Variable.VariablePath.UserPath]=1 }
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.ParameterAst]},$true) | % { $loc[$_.Name.VariablePath.UserPath]=1 }
  $usos=$f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $_.VariablePath.UserPath } | ? { $_ -notmatch ':' } | Sort-Object -Unique -CaseSensitive
  foreach($u in $usos){
    if ($loc.Keys -ccontains $u) { continue }
    $local = $loc.Keys | ? { $_ -ieq $u } | Select-Object -First 1
    if ($local -and ($topo.Keys -ccontains $u)) { "SOMBRA  $($f.Name): usa `$$u (nome do script), mas criou a local `$$local" }
  }
}
