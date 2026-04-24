#################################
#1 Uppsättning av variabler
#################################
Connect-AzAccount -Identity
$subs = Get-AzSubscription
$metaData = @()
$amountObjects = 0
$ClientId ="<ID för Entra App>"
$ClientSecret = "<Secret värdet för Entra App>"
$TenantId = "<Tenant ID i miljön>"

$Endpoint = "<DCE-Endpoint>" 
$DcrId    = "<DCR Immutable ID>"
$Stream   = "<Namn på Streamen>"
$Api = "?api-version=2023-01-01"
#################################
#2 Loop som går igenom varje Key Vault
#################################
foreach ($sub in $subs){
    #förberedning och gör ett ARM REST-API utrop för att hämta akka key vaults i den subscriptionen
    $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
    $uri = "https://management.azure.com/subscriptions/$sub/providers/Microsoft.KeyVault/vaults?api-version=2023-07-01"
    $headers = @{
        Authorization = "Bearer $token"
    }
    $vaults = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    #får igenom varje vault
    foreach ($vault in $vaults.value){
        
        #check om den har en vault uri, om den inte har det kan man inte se secrets
        if(-not $vault.properties.vaultUri){
            Write-Output "Skipping: $($vault.name), check manually"
            continue
        }
        #förbereder och gör ett annat ARM REST-API utrop, denna hämtar alla secrets 
        $secretToken = (Get-AzAccessToken -ResourceUrl "https://vault.azure.net").Token
        $secretHeaders = @{
            Authorization = "Bearer $secretToken"
        }
        $vaultUri = $vault.properties.vaultUri.TrimEnd("/")
        $secretUri = "$vaultUri/secrets?api-version=7.4"
        $secrets = (Invoke-RestMethod -Uri $secretUri -Headers $secretHeaders -Method Get).value
        #check vilken kunde genom RG
        $Kund = "DEMO"
        switch($vault.id.Split("/")[-5]){
            Kund1-KeyVaults {$Kund = "Kund1"}
            RG-KUND2-KEYVAULT {$Kund = "Kund2"}
            rg-Kund3-keyvault {$Kund = "Kund3"}
        }
        #går igenom alla secrets per key vault
        foreach ($secret in $secrets){
            #checkar hur länge tills det går ut
            $expiryDate = [DateTimeOffset]::FromUnixTimeSeconds($secret.attributes.exp)
            $diff =$expiryDate-[DateTimeOffset]::Now
            #under 30 dagar kvar så läggs det till i en lista
            if($diff.Days -lt 30){
                $amountObjects = $amountObjects +1
                $metaData += [PSCustomObject]@{
                TimeGenerated = (Get-Date).ToUniversalTime().ToString("o")
                Kund = $Kund
                VaultName = $vault.name
                Name = $secret.id.Split("/")[-1]
                Expires = [string]$diff.Days + " dagar"
                Enabled = $secret.attributes.enabled
                }
            
            }
        }
        
    
    }
    
}

#################################
#3 All kod för att skicka datan till Log Analytics Workspace
#################################
#förbereder och gör ett annat ARM REST-API utrop som hämtar en token som behövs för att skicka data
$scope = [System.Web.HttpUtility]::UrlEncode("https://monitor.azure.com//.default")   
$body = "client_id=$ClientId&scope=$scope&client_secret=$ClientSecret&grant_type=client_credentials";
$headers = @{"Content-Type" = "application/x-www-form-urlencoded" };
$uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$bearerToken = (Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers).access_token
$headersPOST = @{
    "Authorization" = "Bearer $bearerToken"
    "Content-Type"  = "application/json"
}



$uriPOST = "$Endpoint/dataCollectionRules/$DcrId/streams/$Stream$Api"



#ändrar från att vara lista till en json fil
$json = $metaData | ConvertTo-Json -Depth 10 -Compress
#säkerställer att det är en array som skickas, då om det inte är en så blir det fel i DCR
if ($amountObjects -eq 1){
 $bodyJSON = "[" + $json + "]"   
}else{
    $bodyJSON = $json
}
Write-Output "Sending data to: $uriPOST"
Write-Output "Payload:"
Write-Output $bodyJSON
#skickar json filen
$response = Invoke-RestMethod -Method Post -Uri $uriPOST -Headers $headersPOST -Body $bodyJSON
