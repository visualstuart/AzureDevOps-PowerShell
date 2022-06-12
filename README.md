# AzureDevOps-PowerShell

## Search-PullRequests.ps1
Searches all commit merges in all pull requests after the specified start date, in some or all repositories in the specified Azure DevOps organization and project.

```
.\Search-PullRequests.ps1
    -Organization SomeOrganization
    -Project SomeProject
    [-Repositories Repo1, Repo2]
    -Pattern rexExPattern
    -StartDate 2022-06-01
```

See the NOTE in `Search-PullRequests.ps1` on setting an Azure DevOps personal access token (PAT) in an environment variable.