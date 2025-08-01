# Export all Active Directory users with specified fields to a CSV file

# Import AD module (needed if running on systems without automatic import)
Import-Module ActiveDirectory

# Get all users
$Users = Get-ADUser -Filter * -Properties GivenName,Surname,UserPrincipalName,Enabled,MemberOf,DistinguishedName

# Function to get Organizational Unit (OU) from Distinguished Name
function Get-OUFromDN($dn) {
    if ($dn -match '^CN=.*?,(.*)') {
        return $Matches[1] -replace '^OU=','' -replace ',OU=','\\' -replace ',DC=.*',''
    }
    return '''
}

# Function to get group names
function Get-GroupNames($groups) {
    if ($null -eq $groups) { return '''' }
    return ($groups | ForEach-Object {
        ($_ -split ',')[0] -replace '^CN='
    }) -join '; '
}

# Build output objects
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

# Export to CSV
$Output | Export-Csv -Path .\ADUsersExport.csv -NoTypeInformation -Encoding UTF8

Write-Host "Export complete. File: ADUsersExport.csv"