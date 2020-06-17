param (
    [Parameter(Mandatory)]
    $Run_Test,
    [Parameter(Mandatory)]
    $Block,
    [Parameter(Mandatory)]
    $SessionState
)

& $Run_Test -Block $Block -SessionState $SessionState
