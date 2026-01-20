function New-RandomStataFile {
    param([switch]$WithContinuations)
    
    $commands = @("gen", "replace", "drop", "keep", "sort", "merge", "append", "save", "use")
    $variables = @("var1", "var2", "price", "mpg", "weight", "foreign")
    $operators = @("==", "!=", ">", "<", ">=", "<=")
    
    $lines = @()
    $lineCount = Get-Random -Minimum 3 -Maximum 8
    
    for ($i = 0; $i -lt $lineCount; $i++) {
        $cmd = Get-Random -InputObject $commands
        $var = Get-Random -InputObject $variables
        $line = "$cmd $var"
        
        if ($WithContinuations -and (Get-Random -Maximum 3) -eq 0) {
            $line += " ///"
        }
        
        $lines += $line
    }
    
    return $lines -join [Environment]::NewLine
}

function New-RandomCompoundString {
    $content = -join ((65..90) + (97..122) | Get-Random -Count (Get-Random -Minimum 3 -Maximum 10) | ForEach-Object {[char]$_})
    return '`"' + $content + '"' + "'"
}

function New-RandomTasksJson {
    $taskName = "Task" + (Get-Random -Maximum 1000)
    $command = "echo " + (New-RandomCompoundString)
    $escapedCommand = $command.Replace('"', '\"')
    
    return @"
[
  {
    "label": "$taskName",
    "command": "$escapedCommand"
  }
]
"@
}

function New-RandomKeymapJson {
    $key = "ctrl-" + [char](Get-Random -Minimum 97 -Maximum 123)
    $action = "task::Spawn"
    
    return @"
[
  {
    "bindings": {
      "$key": "$action"
    }
  }
]
"@
}