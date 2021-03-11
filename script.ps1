$new_branch=$args[0]
$from_branch=$args[1]
$repo_url=$args[2]

$script:description = ""
$script:current_file_path = ""
$id_file = Get-Content "D:\workspace\id.txt"
$script:id = [System.Decimal]::Parse($id_file)
Set-Location -Path D:\workspace\rc-pca-zoltanszalontai-RemoteU-System
$current_branch=Invoke-Expression "git branch --show-current"
if($current_branch -ne $new_branch){
    Invoke-Expression "git checkout $from_branch"
    Invoke-Expression "git pull origin $from_branch"
    Invoke-Expression "git checkout -b $new_branch"
    Invoke-Expression "git push origin $new_branch"
}

Set-Location -Path D:\workspace
$repo_name= $repo_url.split("/")[-1].split(".")[0]
if(-Not (Test-Path "D:\workspace\$repo_name" -PathType Container)){
    Invoke-Expression "git clone $repo_url"
}
Set-Location -Path "D:\workspace\$repo_name"
$script:app_branch = Invoke-Expression "git branch --show-current"
$content = ''
foreach ($line in (Get-Content "D:\workspace\rc-pca-zoltanszalontai-RemoteU-System\C4diagrams.yaml")) { $content = $content + "`n" + $line }
$script:c4diagram = ConvertFrom-YAML $content
For ($i=0; $i -lt $script:c4diagram['model']['softwareSystems'].Length.Length; $i++) {
    if($script:c4diagram['model']['softwareSystems'][$i]['name'] -eq 'RemoteU System'){
        $remoteUSystem = $i
        break
    }
}
$script:current_container = @{
    id = "$(($script:id++))";
    tags = 'Element,Container,Internal';
    url = "https://github.com/trilogy-group/$repo_name";
    name = $repo_name;
    description = $repo_name;
    technology = 'AWS Lambda';
    components = @()
}

function getContainerByName {
    param (
        $name
    )

    foreach($c in $script:c4diagram['model']['softwareSystems'][$remoteUSystem]['containers']){
        if($c['name'] -eq $name){
            return $c['id']
        }
    }
}

function getSystemByName {
    param (
        $name
    )

    foreach($c in $script:c4diagram['model']['softwareSystems']){
        if($c['name'] -eq $name){
            return $c['id']
        }
    }
}
$manual_list = @('emailsender', 'github', 'aws', 'dynamo', 'sqs')
$patterns = $manual_list + @('secretsmanager', 'jira', 'xochat', 'registry', 'itops')

function createRelationships {
    param (
        $componentId,
        $interactions
    )
    $relationships = @()
    if($interactions -contains 'jira'){
        $relationships += @{
            id = "$(($script:id++))";
            tags = 'Relationship';
            sourceId = "$componentId";
            destinationId = "$(getSystemByName 'XO Jira')";
            description = 'Get student details'
        }
    }
    if($interactions -contains 'xochat'){
        $relationships += @{
            id = "$(($script:id++))";
            tags = 'Relationship';
            sourceId = "$componentId";
            destinationId = "$(getSystemByName 'XO Chat')";
            description = 'Send error message'
        }
    }
    if($interactions -contains 'registry'){
        $relationships += @{
            id = "$(($script:id++))";
            tags = 'Relationship';
            sourceId = "$componentId";
            destinationId = "$(getContainerByName 'remoteu-registry')";
            description = 'Get modules'
        }
    }
    if($interactions -contains 'itops'){
        $relationships += @{
            id = "$(($script:id++))";
            tags = 'Relationship';
            sourceId = "$componentId";
            destinationId = "$(getSystemByName 'DevFactory Jira')";
            description = 'Get ITOPS ticket details'
        }
    }
    if($interactions -contains 'secretsmanager'){
        $relationships += @{
            id = "$(($script:id++))";
            tags = 'Relationship';
            sourceId = "$componentId";
            destinationId = "$(getContainerByName 'Secrets Managers')";
            description = 'Get credentials'
        }
    }
    return $relationships
}

function getFile {
    param (
        $path_array,
        [Parameter(Mandatory=$false)]
        $update_path = $false
    )
    $python_file_path = "D:\workspace\$repo_name"
    if($path_array.length -gt 1){
        # find directory referenced by first part
        $python_file_path = Invoke-Expression "(ls -r -inc $($path_array[0])).fullname | sort length | select -first 1"
        if(-not $python_file_path){ return @{} }
        # append other directories, if any
        For ($i=1; $i -le $path_array.length-2; $i++) {
            $python_file_path = Join-Path $python_file_path $path_array[$i]
        }
        # append file name
        $python_file_path = Join-Path $python_file_path "$($path_array[-1]).py"
    } else {
        # find the file
        $python_file_path = Invoke-Expression "(ls -r -inc $($path_array[0]).py).fullname"
    }
    if((-not $python_file_path) -or (-not (Test-Path $python_file_path -PathType Leaf))) { return @{} }
    if($update_path) {$script:current_file_path = $python_file_path}
    return Get-Content -Path $python_file_path
}

function checkMethod{
    param (
        $parts,
        [Parameter(Mandatory=$false)]
        $update_desc = $false
    )
    $method_name = $parts[-1]
    [string[]]$python_content = getFile $parts[0..($parts.length-2)] $update_desc
    $result = @()
    $references_to_check = @()
    For ($i=0; $i -lt $python_content.Length; $i++) {
        if($python_content[$i] -like "*def $method_name(*"){
            $exception_decorator = ""
            For ($j=$i-1; $j -ge 0 -And $j -ge $i-4; $j--) {
                $exception_decorator = -join($python_content[$j], $exception_decorator)
                if ($exception_decorator.Contains("@exception_decorator")){
                    if($exception_decorator | Select-String -Pattern 'notify_xo_chat\s*=\s*True'){
                        $result += "xochat"
                    }
                    if($update_desc){
                        $capture = $exception_decorator | Select-String -Pattern 'functionality\s*=\s*[''"](.+)[''"].*'
                        if($capture.Matches){
                            $script:description = $capture.Matches.groups[1].value
                        }
                    }
                    break
                }
            }
            For ($j=$i+1; $j -lt $python_content.Length -And (-Not ($python_content[$j] -like "*def *")); $j++) {
                foreach ($wanted in $patterns) {
                    if ($python_content[$j] -like "*$wanted*"){
                        $result += $wanted
                    }
                }
                $capture = $python_content[$j] | Select-String -AllMatches -Pattern '([^\s"''\[\]\(\)]+)\('
                if($capture.Matches){
                    $capture.Matches | ForEach-Object {
                        if((-not ($references_to_check -contains $_.groups[1].value)) -and (-not ($_.groups[1].value.startsWith("."))) -and (-not ($_.groups[1].value.startsWith("@")))){
                            $references_to_check += $_.groups[1].value
                        }
                    }
                }
            }
            break
        }
    }
    #Write-Host "Found method calls in $method_name : $references_to_check"
    foreach ($line in $python_content){
        foreach ($reference in $references_to_check){
            $split = $reference.split(".")
            if($split[0] -eq "self"){
                $split = $split[1..($split.length-1)] 
            }
            $new_parts = @()
            if($split.length -eq 1){
                $match = $line | Select-String -Pattern "from ([^\s]+) import $reference$"
                if($match.Matches){
                    #Write-Host "Checking $($match.Matches.groups[1].value.split('.') + $reference)"
                    $new_parts = $match.Matches.groups[1].value.split(".") + $reference
                } elseif($line -like "*def $reference*") {
                    #Write-Host "Checking $reference within same file"
                    $new_parts = $parts[0..($parts.length-2)] + $reference
                }
            } else{
                $match = $line | Select-String -Pattern "from ([^\s]+) import $($split[0])$"
                if($line -like "import $($split[0])") {
                    For ($i=0; $i -le $parts.length-3; $i++) {
                        $new_parts += $parts[$i]
                    }
                    $new_parts += $split
                    #Write-Host "Checking $reference within same module: $new_parts"
                } elseif($match.Matches){
                    $new_parts = $match.Matches.groups[1].value.split('.') + $split
                    #Write-Host "Checking in another module: $new_parts"
                }
            }
            if($new_parts.length -gt 0){
                $result = $result + (checkMethod $new_parts)
            }
        }
    }
    return $result | Select-Object -Unique
}

function processComponent {
    param (
        $componentName,
        $handler
    )
    $script:description = ""
    $interactions = checkMethod $handler.split(".") $true
    if($script:description.Length -le 1){
        $script:description = $handler
    }

    $split = $script:current_file_path.split('\')
    $split = $split[3..($split.length-1)]
    $component = @{
        id = "$(($script:id++))";
        tags = 'Element,Component,Internal';
        url = "https://github.com/trilogy-group/$repo_name/blob/$script:app_branch/$($split -join '/')";
        name = $componentName;
        description = $script:description;
        relationships = @();
        technology = 'Lambda Python';
        size = 0
    }

    $component['relationships'] = createRelationships $component['id'] $interactions
    foreach($interaction in $interactions){
        if($manual_list -contains $interaction){
            Write-Host "Take care of $interaction in $handler manually"
        }
    }
    $script:current_container['components'] += $component
}

if(Test-Path "D:\workspace\$repo_name\serverless.yml" -PathType Leaf){
    $apis = ''
    Import-Module powershell-yaml
    [string[]]$fileContent = Get-Content "D:\workspace\$repo_name\serverless.yml"
    $content = ''
    foreach ($line in $fileContent) { $content = $content + "`n" + $line }
    $yaml = ConvertFrom-YAML $content
    $yaml["functions"].GetEnumerator() | ForEach-Object {
        processComponent $_.key $_.value["handler"]
        $_.value["events"] | ForEach-Object -Process {
            if($_ -And $_["http"]){
                $path=$_["http"]["path"]
                $method=$_["http"]["method"]                
                $apis += @"
    -
        path: "{env}/$path"
        description: >-
            $script:description
        method: $method
        container: $repo_name
        parameters:
            email:
                mandatory: true
                description: >-
                   email of student
        body_example: >
            {}
"@
            }
        }
    }
    $yaml['resources']['Resources'].GetEnumerator() | ForEach-Object {
        if($_.value['Type' -eq 'AWS::SQS::Queue']){
            $script:current_container['components'] += @{
                id = "$(($script:id++))";
                tags = 'Element,Component,Internal';
                url = "https://github.com/trilogy-group/$repo_name/blob/$script:app_branch/serverless.yml";
                name = $_.key;
                description = $_.key;
                relationships = @();
                technology = 'AWS SQS';
                size = 0
            }
        }
        if($_.value['Type' -eq 'AWS::DynamoDB::Table']){
            $script:current_container['components'] += @{
                id = "$(($script:id++))";
                tags = 'Element,Component,Internal';
                url = "https://github.com/trilogy-group/$repo_name/blob/$script:app_branch/serverless.yml";
                name = $_.key;
                description = $_.key;
                relationships = @();
                technology = 'AWS DynamoDB';
                size = 0
            }
        }
    }
    Set-Content "D:\workspace\id.txt" $script:id
    $script:c4diagram['model']['softwareSystems'][$remoteUSystem]['containers'] += $script:current_container
    $diagram = @{
        'key' = $script:current_container['name'] -replace '-','';
        'paperSize' = 'A4_Landscape';
        'containerId' = $script:current_container['id'];
        'externalContainerBoundariesVisible' = 'false';
        'elements' = @();
        'animations' = @();
        'relationships' = @()
    }
    foreach($component in $current_container['components']){
        $diagram['elements'] += @{
            'id' = $component['id'];
            'x' = 10;
            'y' = 10
        }
        foreach($relationship in $component['relationships']){
            $diagram['elements'] += @{
                'id' = $relationship['destinationId'];
                'x' = 10;
                'y' = 10
            }
            $diagram['relationships'] += @{
                'id' = $relationship['id']
            }
        }
    }
    $script:c4diagram['views']['componentViews'] += $diagram
    (ConvertTo-Json -InputObject $script:c4diagram -Depth 100) -replace '(?ms)relationships":  (\{[^\}]+\})', 'relationships":  [$1]'| Out-File "D:\workspace\$($new_branch)_c4.json"
    Add-Content -Path D:\workspace\rc-pca-zoltanszalontai-RemoteU-System\api.yaml -Value $apis
    Set-Location -Path D:\workspace\
}
