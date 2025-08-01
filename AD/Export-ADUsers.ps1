Import-Module ActiveDirectory

# Function to get properly ordered OU path
function Get-OUFromDN($dn) {
    # Extract all OU=... elements (in order from leaf to root)
    $ous = ($dn -split ',') | Where-Object { $_ -like 'OU=*' }
    if ($ous) {
        # Remove "OU=" prefix and reverse to get root-to-leaf order
        return (($ous | ForEach-Object { $_ -replace '^OU=' })[-1..-($ous.Count)]) -join '\\'
    }
    return ''
}

function Get-GroupNames($groups) {
    if ($null -eq $groups) { return '' }
    return ($groups | ForEach-Object {
        ($_ -split ',')[0] -replace '^CN='
    }) -join '; '
}

$Users = Get-ADUser -Filter * -Properties GivenName,Surname,UserPrincipalName,Enabled,MemberOf,DistinguishedName

$Output = $Users | ForEach-Object {
    [PSCustomObject]@{
        FirstName     = $_.GivenName
        LastName      = $_.Surname
        UPN           = $_.UserPrincipalName
        OU            = Get-OUFromDN $_.DistinguishedName
        Groups        = Get-GroupNames $_.MemberOf
        Enabled       = if ($_.Enabled) { "Enabled" } else { "Disabled" }
    }
}

$Output | Export-Csv -Path .\ADUsersExport.csv -NoTypeInformation -Encoding UTF8

Write-Host "Export complete. File: ADUsersExport.csv"