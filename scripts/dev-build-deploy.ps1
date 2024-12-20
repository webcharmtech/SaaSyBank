Write-Host " $(Split-Path -Leaf $PSCommandPath) ..." -ForegroundColor White -BackgroundColor DarkBlue

. ./get-ElapsedTimeFormatted.ps1

$startTime = Get-Date
# $formattedElapsedTime = Get-ElapsedTimeFormatted -startTime $startTime
# Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime."

$commonConstants = ./common-constants.ps1
Set-Variable -Name 'TEMPLATE_FILE' -Value './template.yaml' -Option Constant 

Write-Output "`n$(Get-Date -Format 'HH:mm:ss') Validating the cloudformation template .."
sam validate --template-file $TEMPLATE_FILE --lint # | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() }
if ($LASTEXITCODE -eq 0) {
    Write-Output "`n$(Get-Date -Format 'HH:mm:ss') Starting a build, stack '$($commonConstants.stackName)' .."

    Write-Output "`n$(Get-Date -Format 'HH:mm:ss') Preparing lambda layers .."

    $projectFolder = (Get-Location).Path + "/.."

    Write-Host "Skipping postgresql layer build !" -ForegroundColor Yellow -BackgroundColor DarkGreen
    # Set-Location "${projectFolder}/backend/layers/pg/nodejs/"
    # npm install
    # Set-Location ..
    # Compress-Archive -Update -Path * -DestinationPath ../pg-layer.zip

    Set-Location "${projectFolder}/scripts/"

    Write-Output "`n$(Get-Date -Format 'HH:mm:ss') sam build --template-file $TEMPLATE_FILE ..`n"
    sam build --template-file $TEMPLATE_FILE # > $null
    if ($LASTEXITCODE -eq 0) {
        $ecrBankingRepositoryName = "banking-repository"
        $bankingServiceName = "banking-service"

        $accountId = aws sts get-caller-identity --query "Account" --output text
        # Write-Host "Skipping docker build and push !" -ForegroundColor Yellow -BackgroundColor DarkGreen
        $bankingDockerResults = @{ecrImageUri = "${accountId}.dkr.ecr.eu-central-1.amazonaws.com/${ecrBankingRepositoryName}:20241118-2344" }
        # ./dev-build-push-docker-image.ps1 `
        #     -accountId $accountId `
        #     -ecrRepositoryName $ecrBankingRepositoryName `
        #     -serviceName $bankingServiceName

        $formattedElapsedTime = Get-ElapsedTimeFormatted -startTime $startTime
        Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime : Build completed. Deploying .."

        # Build the parameter overrides string dynamically
        if ($commonConstants.isMainBranch -ne $true) {
            $allowRDSPublicAccess = 'true'
        }
        $parameterOverrides = @(
            # "ExistingVpcId='vpc-08016eb77e7ac9962'",
            # "ExistingUserPoolId='eu-central-1_OHq1aZYju'",
            # "ExistingIdentityPoolId='eu-central-1:e9f848f2-a3ed-43f9-8ddb-833ca34233ba'",
            # "ExistingCognitoDomain='ena-575491442067.auth.eu-central-1.amazoncognito.com'",
            # "ExistingNotesEncryptionKeyId='d0efc261-b71d-4f5c-9686-9876cc664243'",
            # "ExistingElasticacheRedisClusterAddress='en-elasticache-redis-cluster.hz2zez.0001.euc1.cache.amazonaws.com:6379'",
            "BankingServiceName='$bankingServiceName'",
            "BankingTaskEcrImageUri='$($bankingDockerResults.ecrImageUri)'",
            "AllowRDSPublicAccess='$allowRDSPublicAccess'"
        )

        if ($commonConstants.isMainBranch) {
            $parameterOverrides += "StageName='prod'"
        }
        else {
            # In feature branch, reuse the follwing resources from the main branch's stack:
        }

        # Join the parameter overrides into a single string
        $parameterOverridesString = $parameterOverrides -join " "

        # CAPABILITY_IAM: This capability allows AWS CloudFormation to create IAM resources (such as roles and policies) on your behalf
        sam deploy --region $commonConstants.region --template-file $TEMPLATE_FILE --stack-name $commonConstants.stackName `
            --capabilities CAPABILITY_IAM `
            --fail-on-empty-changeset false `
            --resolve-s3 `
            --parameter-overrides $parameterOverridesString
        $formattedElapsedTime = Get-ElapsedTimeFormatted -startTime $startTime
        if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne 1)) {
            Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime : Deployment failed with exit code ${LASTEXITCODE}."
        }
        else {
            if ($LASTEXITCODE -eq 1) {
                Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime : Deployment completed with no changes to deploy. Stack $($commonConstants.stackName) is up to date."
            }
            else {
                Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime : Deployment completed successfully."
                ./update-postman-collection.ps1
            }
        }
    }
    else {
        $formattedElapsedTime = Get-ElapsedTimeFormatted -startTime $startTime
        Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime : SAM build failed."
    }
}

$formattedElapsedTime = Get-ElapsedTimeFormatted -startTime $startTime
Write-Output "`n$(Get-Date -Format 'HH:mm:ss'), elapsed $formattedElapsedTime : Completed."