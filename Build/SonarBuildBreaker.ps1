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

    # Represents the absolute path to the ".sonarqube" folder generated by the "dotnet-sonarscanner" tool.
    [String]
    [Parameter(Mandatory = $true)]
    $DotSonarQubeFolder,

    # Represents the maximum amount of retries before giving up and considering that the current build 
    # failed to pass the quality gate (Sonar).
    [int]
    [Parameter(Mandatory = $false)]
    $MaxNumberOfTries = 30,

    # Represents the number of milliseconds to wait before trying again to see whether the current build 
    # has passed quality gate (Sonar).
    [int]
    [Parameter(Mandatory = $false)]
    $SleepingTimeInMillis = 10000
)

$SonarTaskFile = "$DotSonarQubeFolder\out\.sonar\report-task.txt"

$ProjectKey = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'projectKey=' }
$ProjectKey = $ProjectKey -replace "projectKey=" -replace ""

$ServerUrl = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'serverUrl=' }
$ServerUrl = $ServerUrl.Split('=')[1]

$CeTaskUrl = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'ceTaskUrl=' }
$CeTaskUrl = $CeTaskUrl -replace "ceTaskUrl=" -replace ""

$DashboardUrl = Get-Content -Path $SonarTaskFile | Where-Object { $_ -Match 'dashboardUrl=' }
$DashboardUrl = $DashboardUrl.Split('=')[1]

$TokenAsBytes = [System.Text.Encoding]::UTF8.GetBytes(("$SonarToken" + ":"))
$Base64Token = [System.Convert]::ToBase64String($TokenAsBytes)
$AuthorizationHeaderValue = [String]::Format("Basic {0}", $Base64Token)
$Headers = @{ 
    Authorization = $AuthorizationHeaderValue; 
    AcceptType    = "application/json"  
}

$Response = Invoke-WebRequest -Uri $CeTaskUrl -Headers $Headers -UseBasicParsing | ConvertFrom-Json
$AnalysisUrl = "{0}/api/qualitygates/project_status?analysisId={1}" -f $ServerUrl, $Response.task.analysisId
$NumbersOfTries = 0

do {
    Start-Sleep -Milliseconds $SleepingTimeInMillis

    $Response = try { 
        (Invoke-WebRequest -Uri $AnalysisUrl -Headers $Headers).BaseResponse
    }
    catch [System.Net.WebException] { 
        $_.Exception.Response 
    } 

    $StatusCodeAsInt = [int]$Response.BaseResponse.StatusCode

    if ($StatusCodeAsInt -ne 200) {
        $NumbersOfTries++
        Write-Output "`n${NumbersOfTries}: Failed to fetch Sonar analysis results; will check again in $SleepingTimeInMillis milliseconds"
        continue
    }
    elseif (($Response.projectStatus.status -ne 'OK') -and ($Response.projectStatus.status -ne 'NONE')) {
        break
    }
    elseif (($Response.projectStatus.status -eq 'OK') -and ($Response.projectStatus.status -eq 'NONE')) {
        Write-Output "`n`nOK: Quality gate PASSED - please check it here: $ServerUrl/dashboard?id=$ProjectKey"
        exit 0
    }
    
} while ($NumbersOfTries -lt $MaxNumberOfTries)

Write-Output "##vso[task.LogIssue type=error;]`n`n NOTOK: Quality gate FAILED - please check it here: $ServerUrl/dashboard?id=$ProjectKey"
Write-Output "##vso[task.complete result=Failed;]"
exit 1