# Based on: https://github.com/michaelcostabr/SonarQubeBuildBreaker/blob/master/SonarQubeBuildBreaker.ps1
# 
# SonarCloud Web API
#       Methods: https://sonarcloud.io/web_api/api/
#       Authentication: https://docs.sonarqube.org/display/DEV/Web+API#WebAPI-UserToken.
Param (
    # Represents the token used for authenticating against SonarCloud.
    [String]
    [Parameter(Mandatory = $true)]
    $SonarToken,

    # Represents the absoulte path to the ".sonarqube" folder generated by the "dotnet-sonarscanner" tool.
    [String]
    [Parameter(Mandatory = $true)]
    $DotSonarQubeFolder
)

$SonarTaskFile = "$DotSonarQubeFolder\out\.sonar\report-task.txt"

$ProjectKey = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'projectKey=' }
$ProjectKey = $ProjectKey -replace "projectKey=" -replace ""

$ServerUrl = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'serverUrl=' }
$ServerUrl = $ServerUrl.Split('=')[1]

$CeTaskUrl = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'ceTaskUrl=' }
$CeTaskUrl = $CeTaskUrl -replace "ceTaskUrl=" -replace ""

$DashboardUrl  = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'dashboardUrl=' }
$DashboardUrl  = $DashboardUrl.Split('=')[1]

$TokenAsBytes = [System.Text.Encoding]::UTF8.GetBytes(("$SonarToken" + ":"))
$Base64Token = [System.Convert]::ToBase64String($TokenAsBytes)
$AuthorizationHeaderValue =  [String]::Format("Basic {0}", $Base64Token)
$Headers = @{ 
    Authorization = $AuthorizationHeaderValue; 
    AcceptType = "application/json"  
}

$Response = Invoke-WebRequest -Uri $CeTaskUrl -Headers $Headers -UseBasicParsing | ConvertFrom-Json

$AnalysisUrl = "{0}/api/qualitygates/project_status?analysisId={1}" -f $ServerUrl, $Response.task.analysisId
$Response = Invoke-WebRequest -Uri $AnalysisUrl -Headers $Headers -UseBasicParsing | ConvertFrom-Json

if (($Response.projectStatus.status -ne 'OK') -and ($Response.projectStatus.status -ne 'NONE')) {
      $ErrorMsg = "##vso[task.LogIssue type=error;] Quality gate FAILED. Please check it here: {0}/dashboard?id={1}" -f $ServerUrl, $ProjectKey
      Write-Host $ErrorMsg
      Write-Host "##vso[task.complete result=Failed;]"
}