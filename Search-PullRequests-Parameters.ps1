# Define common parameters for Search-PullRequests.ps1 suitable for splatting.
#
# Suggested use at the PowerShell prompt:
#
#   $params = .\Search-PullRequests-Parameters.ps1
#   .\Search-PullRequests.ps1 -Pattern somePattern -StartDate 2022-06-01 @params
#   .\Search-PullRequests.ps1 -Pattern anotherPattern -StartDate 2022-06-08 @params

@{
    # ADO organization
    Organization = "someOrganization"
    
    # ADO project containing repositories and pull requests
    Project = "someProject"
    
    # ADO repositories to search; if not specified then search all repositories in project
    Repositories =
        "Repo1",
        "Repo2"
}