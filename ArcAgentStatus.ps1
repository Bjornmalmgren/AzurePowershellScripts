Connect-AzAccount -Identity

$subs = Get-AzSubscription
#################################
#1 deklaration av all variabler som kommer användas i skriptete
#################################
$allArc = @()
$amountObjects = 0
$ClientId ="<ID för Entra App>"
$ClientSecret = "<Secret värdet för Entra App>"
$TenantId = "<Tenant ID i miljön>"

$Endpoint = "<DCE-Endpoint>" 
$DcrId    = "<DCR Immutable ID>"
$Stream   = "<Namn på Streamen>"
$api = "?api-version=2023-01-01"
#################################
#2 kod som körs för att hitta ARC agenter i alla servar
#################################
foreach ($sub in $subs){


Set-AzContext -Subscription $sub -WarningAction SilentlyContinue | Out-Null

#Förbereder och gör ett ARM REST-API utrop, detta hämtar alla servar i en subscription
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
$headers = @{ Authorization = "Bearer $token" }
$uri = "https://management.azure.com/subscriptions/$sub/providers/Microsoft.HybridCompute/machines?api-version=2022-12-27"
$result = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET

$machines = $result.value
#loopar igenom alla servrar
foreach ($m in $machines) {
    #checka vilken kund det är
    switch($m.id.Split("/")[4]) {
        "Kund1-RG-ARC" {$Kund = "Kund1"}
        "Kund2-RG-ARC" {$Kund = "Kund2"}
        "Kund3-RG-ARC" {$Kund = "Kund3"}
        "Kund4-RG-ARC" {$Kund = "Kund4"}
    }
    #om arc agenten inte är konnekted så läggs den till i en lista
    if ($m.properties.status -ne "Connected"){
        $amountObjects = $amountObjects + 1
        $allArc += [PSCustomObject]@{
            TimeGenerated = (Get-Date).ToUniversalTime().ToString("o")
            Name     = $m.name
            Kund     = $Kund
            OS       = $m.properties.osName
            Status   = $m.properties.status
        }
    }
    
}
}
Set-AzContext -tenant $TenantId
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

$uriPOST = "$Endpoint/dataCollectionRules/$DcrId/streams/$Stream$api"



#ändrar från att vara lista till en json fil
$json = $allArc | ConvertTo-Json -Depth 10 -Compress
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
