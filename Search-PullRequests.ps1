# Search-PullRequests searches for patterns of strings in the merge commits of pull requests.
#
# NOTE: requires the environment variable AzureDevOpsPAT to be set with a valid Azure DevOps
# personal access token (PAT).
#
# It was challenging to determine which custom access permissions to grant to the PAT. On the other
# hand, granting full access is not recommended for security reasons. Consider mitigating providing
# too much access by making the token expire quickly.
#
# For details on Azure DevOps PAT, see
# https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate

Param (
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $false)] # if not specified then search all repositories in project
    [string[]]$Repositories,

    # Specifies the text to find on each line in each merge commit in each pull request in each
    # repository in the project. The pattern value is treated as a regular expression.
    #
    # For details on regular expressions, see
    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions
    [Parameter(Mandatory = $true)]
    [string]$Pattern,

    [Parameter(Mandatory = $true, HelpMessage="Starting date in ISO 8601 format, e.g., 2022-06-01")]
    [string]$StartDate    
)

# create basic auth header from AzureDevOpsPAT environment variable 
$AzureDevOpsAuthenicationHeader =
    @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($Env:AzureDevOpsPAT)")) }

$apiVersion = "api-version=7.0"

$organizationUrl = "https://dev.azure.com/$($Organization)"

$startHoursZuluTime = "T00:00:00.0000000Z"
$startDateTime = "$($StartDate)$($startHoursZuluTime)"

$now = Get-Date -Format "yyyy-MM-dd HHmm"

# NOTE: using $Pattern, which is a regex, in the filename could lead to an invalid filename due to
# special characters. Consider ways to sanitize the $Pattern value.
$outputFilename = "Pull Requests containing $($Pattern) since $($StartDate) as of $($now).csv"

function ParseDateTime($dateTimeString) {
    return [DateTime]::ParseExact($dateTimeSTring, "yyyy-MM-ddTHH:mm:ss.fffffffZ", $null) 
}

# Get functions: access GET methods of the Azure DevOps REST API

function Invoke-AdoGetRestMethod ($uri) {
    return Invoke-RestMethod -Uri $uri -Method get -Headers $AzureDevOpsAuthenicationHeader
}

function Get-Repositories {
    return Invoke-AdoGetRestMethod( `
        "$($organizationUrl)/$($Project)/_apis/git/repositories?$($apiVersion)")
}

function Get-CompletedPullRequests($repository) {
    return Invoke-AdoGetRestMethod( `
        "$($repository.url)/pullrequests?searchCriteria.status=completed&searchCriteria.includeLinks=true&$($apiVersion)")
}

function Get-MergeCommit($pullRequest) { `
    return Invoke-AdoGetRestMethod($pullRequest._links.mergeCommit.href)
}

function Get-CommitChanges($commit) { `
    return Invoke-AdoGetRestMethod($commit._links.changes.href)
}

function Get-CommitChangeItem($commitChange) { `
    try {
        return Invoke-AdoGetRestMethod($commitChange.item.url)
    }
    catch {
        # An exception is thrown under certain (undefined) circumstances. One of them is if
        # $commitChange.changeType is "delete", however there are apparently others. Suppressing
        # the exception for now.
        #
        # Write-Host "Error getting $($commitChange.item.url)"
    }   
}

# Select functions: project objects onto a PsObject instance's properties

function Select-Repository($repository) {
    return New-Object psobject -Property @{
        Repository = $repository.name
    }
}

function Select-PullRequest($pullRequest) {
    return New-Object psobject -Property @{
        "PR ID" = $pullRequest.pullRequestId
        "PR URL" = "$($pullRequestUrl)/$($pullRequest.pullRequestId)"
        "PR Title" = $pullRequest.title
        "PR Creation Date" = ParseDateTime($pullRequest.creationDate) 
        "PR Created By" = $pullRequest.createdBy.displayName
        "PR Closed Date" = ParseDateTime($pullRequest.closedDate)
        "PR Source" = $pullRequest.sourceRefName
        "PR Target" = $pullRequest.targetRefName
    }
}

function Select-CommitChangePath($commitChange) {
    return New-Object psobject -Property @{
        "File Path" = $commitChange.item.path
    }
}

function Select-CommitChangePathUrl($commitChange) {
    return New-Object psobject -Property @{
        "File URL" = "$($pullRequestUrl)/$($pullRequest.pullRequestId)?_a=files&path=$($commitChange.item.path)"
    }
}

function Select-MatchingLine($matchingLine) {
    return New-Object psobject -Property @{
        "Line Number" = $matchingLine.LineNumber
        "Line" = $matchingLine.Line
    }
}

# accumulate output rows (records)

$outputRows = @()

# for each repository in the ADO project
foreach ($repository in (Get-Repositories).value | Sort-Object -Property name)
{
    $matchInRepository = $false

    # filter to repositories if specified
    if (($null -eq $Repositories) -or 
        ($Repositories -contains $repository.name))
    {
        # url for pull request UI page
        $pullRequestUrl = "$($organizationUrl)/$($Project)/_git/$($repository.name)/pullrequest"
        
        foreach ($pullRequest in (Get-CompletedPullRequests($repository)).value.`
            where{$_.closedDate -ge $startDateTime} | `
            Sort-Object -Property closedDate -Descending)
        {
            $matchInPullRequest = $false
            
            $commit = Get-MergeCommit($pullRequest)
            $commitChanges = Get-CommitChanges($commit)
            
            foreach ($commitChange in $commitChanges.changes.`
                where{$_.changeType -ne "delete"})
            {
                $item = Get-CommitChangeItem($commitChange)

                # if item is of type string, then it is the contents of the merge
                if (($null -ne $item) -and ($item.GetType() -eq [string]))
                {
                    # split the string into lines, then select the pattern on each line
                    $matchingLines = `
                        $item -split '\r?\n' |`
                        Select-String -Pattern $Pattern
                    if ($matchingLines.Count -ne 0)
                    {
                        if (!$matchInRepository)   # first match within repository
                        {
                            $outputRows += Select-Repository($repository)
                            $matchInRepository = $true
                        }

                        if (!$matchInPullRequest)   # first match within pull request
                        {
                            $outputRows += Select-PullRequest($pullRequest)
                            $matchInPullRequest = $true
                        }
    
                        $outputRows += Select-CommitChangePath($commitChange)
                        $outputRows += Select-CommitChangePathUrl($commitChange)

                        foreach ($matchingLine in $matchingLines)
                        {
                            $outputRows += Select-MatchingLine($matchingLine)
                        }
                    }
                }
            }
        }
    }
}

# export output rows as CSV

$outputRows |
    Select-Object -Property `
        "Repository",
        "PR ID", "PR URL", "PR Title",
            "PR Created By", "PR Creation Date", "PR Closed Date",
            "PR Source", "PR Target", spacer0,
        "File Path", "File URL",
        "Line Number", "Line" | 
    Export-Csv -Path $outputFilename -NoTypeInformation