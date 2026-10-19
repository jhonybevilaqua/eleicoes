param($arq)
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $arq),[ref]$null,[ref]$null)
$auto='_','args','true','false','null','PSScriptRoot','PSCommandPath','Matches','PID','LASTEXITCODE','input','this','PSItem','Host','ErrorActionPreference','ProgressPreference','env','PSVersionTable','foreach','Error','HOME','ExecutionContext','MyInvocation','PSBoundParameters','OFS','PWD','IsWindows','IsLinux','PSDefaultParameterValues','VerbosePreference','WarningPreference','ConfirmPreference'
$fns=$ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)
function Dentro($n){ foreach($f in $fns){ if($n.Extent.StartOffset -ge $f.Extent.StartOffset -and $n.Extent.EndOffset -le $f.Extent.EndOffset){return $true} }; $false }
$topo=@{}
$ast.FindAll({$args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -or $args[0] -is [System.Management.Automation.Language.ForEachStatementAst]},$true) | % {
  $v = if($_ -is [System.Management.Automation.Language.ForEachStatementAst]){$_.Variable}else{$_.Left}
  $v.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $n=$_.VariablePath.UserPath -replace '^script:',''; if(-not (Dentro $_) -or $_.VariablePath.UserPath -like 'script:*'){ $topo[$n]=1 } }
}
if ($ast.ParamBlock) { $ast.ParamBlock.Parameters | % { $topo[$_.Name.VariablePath.UserPath]=1 } }
foreach($f in $fns){
  $def=@{}
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.AssignmentStatementAst]},$true) | % { $_.Left.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $def[$_.VariablePath.UserPath]=1 } }
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.ForEachStatementAst]},$true) | % { $def[$_.Variable.VariablePath.UserPath]=1 }
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.ParameterAst]},$true) | % { $def[$_.Name.VariablePath.UserPath]=1 }
  if($f.Parameters){ $f.Parameters | % { $def[$_.Name.VariablePath.UserPath]=1 } }
  $f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.ConvertExpressionAst] -and $args[0].Type.TypeName.Name -eq 'ref'},$true) | % { $_.Child.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $def[$_.VariablePath.UserPath]=1 } }
  $usos=$f.Body.FindAll({$args[0] -is [System.Management.Automation.Language.VariableExpressionAst]},$true) | % { $_.VariablePath.UserPath } | ? { $_ -notmatch ':' } | Sort-Object -Unique
  foreach($u in $usos){
    if($auto -contains $u){continue}
    if($def.ContainsKey($u)){continue}
    $caso = $topo.Keys | ? { $_ -ieq $u } | Select-Object -First 1
    if(-not $caso){ "SEM DEFINICAO  $($f.Name): `$$u" }
    elseif($caso -cne $u){ "CASO DIFERENTE $($f.Name): `$$u -> script `$$caso" }
  }
}
