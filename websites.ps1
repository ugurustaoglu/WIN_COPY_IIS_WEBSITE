function Invoke-SQL {
    param(
        [string] $SQLServer = "SERVERIP",
        [string] $SQLDBName = "DBNAME",
        [string] $SqlQuery = $(throw "Please specify a query."),
        [string] $uid = "UID",
        [string] $pwd = "PWD"
      )
$SQLServer = "SERVERIP"
$SQLDBName = "DBNAME"
$uid ="UID"
$pwd = "PWD"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName;User ID = $uid; Password = $pwd;"
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.CommandText = $SqlQuery
$SqlCmd.Connection = $SqlConnection
$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$SqlAdapter.SelectCommand = $SqlCmd
$DataSet = New-Object System.Data.DataSet
$SqlAdapter.Fill($DataSet)
$SqlConnection.Close()
Return $DataSet.Tables[0]
#$SqlAdapter.Fill($DataSet)
#$DataSet.Tables[0] | out-file "C:\Scripts\xxxx.csv"
}

$strDBServer = 'SERVERWHEREYOUCOPYTHEWEBSITEFROM'
$UsernameS = 'USERNAMEWHEREYOUCOPYTHEWEBSITEFROM'
$PasswordS = 'PASSWORDWHEREYOUCOPYTHEWEBSITEFROM'
$strSvr = 'DESTINATIONSERVERWHEREYOUCREATETHEWEBSITE'
$UsernameR = 'USERNAMEOFDESTINATIONSERVERWHEREYOUCREATETHEWEBSITE'
$PasswordR = 'PASSWORDOFDESTINATIONSERVERWHEREYOUCREATETHEWEBSITE'
$domainS = 'DOMAINWHEREYOUCOPYTHEWEBSITEFROM'
$domainR = 'DOMAINDESTINATIONSERVERWHEREYOUCREATETHEWEBSITE'
$passS = ConvertTo-SecureString -AsPlainText $PasswordS -Force
$passR = ConvertTo-SecureString -AsPlainText $PasswordR -Force
$CredS = New-Object System.Management.Automation.PSCredential -ArgumentList $UsernameS,$passS
$CredR = New-Object System.Management.Automation.PSCredential -ArgumentList $UsernameR,$passR


$RecordSet = Invoke-SQL -sqlQuery "SELECT *,RIGHT(RTRIM(FullName),4) FROM [Win2016Mig].[dbo].[IISPaths] IIS JOIN [Win2016Mig].[dbo].[ServerBindings] B ON IIS.WebSiteId= B.WebSiteId WHERE RIGHT(RTRIM(FullName),4) Like 'ROOT' AND  IIS.ServerName='$strDBServer' AND  B.ServerName='$strDBServer';"
$RecordSet2 = Invoke-SQL -sqlQuery "SELECT *,RIGHT(RTRIM(FullName),4) FROM [Win2016Mig].[dbo].[IISPaths] IIS JOIN [Win2016Mig].[dbo].[ServerBindings] B ON IIS.WebSiteId= B.WebSiteId WHERE RIGHT(RTRIM(FullName),4) Not Like 'ROOT' AND  IIS.ServerName='$strDBServer' AND  B.ServerName='$strDBServer';"



$s = New-PSSession -ComputerName $strSvr  -credential $CredR
$counter = 0
foreach ($Row in $RecordSet) { 
	$counter=$counter+1 
	if ( $counter -eq 1) {continue}
	
	$Path=$Row.Path.trim()
	$PoolId=$Row.PoolId.trim()
	$ServerComment= $Row.ServerComment.trim()
	$WebsiteId= $Row.WebsiteId.trim()
	$Hostname= $Row.Hostname.trim()
	$IP= $Row.IP.trim()
	$Port= $Row.Port.trim()

	
$pathExt = $Path -replace ':','$'
$pathS = "\\$strDBServer\$pathExt"
$pathR = "\\$strSvr\$pathExt"
	

	Invoke-Command -Session $s -ScriptBlock {param($Path)New-Item -Path $Path -type directory -Force } -ArgumentList $Path

	 New-PSDrive -Name "SOURCE" -PSProvider "FileSystem" -Root $pathS -credential $credS
	 New-PSDrive -Name "DEST" -PSProvider "FileSystem" -Root $pathR -credential $credR
	 Copy-Item "$pathS\*" -Destination $pathR -recurse
	 Remove-PSDrive -Name "SOURCE" -Force
	 Remove-PSDrive -Name "DEST" -Force
	$RecordSetSec = Invoke-SQL -sqlQuery "SELECT * FROM [Win2016Mig].[dbo].[Security] WHERE ServerName='$strDBServer' and ServerDomain='$domainS' AND TrusteeDomain <> '' AND ([Path] = '$Path' OR [Path] LIKE '$Path\%') ;"
	$RecordSetSec
	$sd = ([wmiclass]'Win32_SecurityDescriptor').psbase.CreateInstance()
	foreach ($RowSec in $RecordSetSec) { 
		$trustee = ([wmiclass]'Win32_trustee').psbase.CreateInstance()
		If ($RowSec.TrusteeDomain.trim() -eq $strDBServer) {
			$trustee.Domain =$strSvr
		}
		else {
			$trustee.Domain = $RowSec.TrusteeDomain.trim()
		}
		write-Output $trustee.Domain
		$trustee.Name = $RowSec.Trustee.trim()
		$ace = ([wmiclass]'Win32_ACE').psbase.CreateInstance()
		$ace.AccessMask = $RowSec.AccessMask.trim()
		$ace.AceFlags = $RowSec.AceFlags.trim()
		$ace.AceType = $RowSec.AceType.trim()
		$ace.Trustee = $trustee
		$sd.DACL += $ace
		}
	$sd.ControlFlags = $RowSec.ControlFlags.trim()
    # Read the existing permissions
    $wmiPath = $Path.Replace("\","\\")
    $settings = Get-WmiObject -Class Win32_LogicalFileSecuritySetting -Filter "Path='$wmiPath'" -ComputerName $strSvr -Credential $CredR
	$security = $settings.GetSecurityDescriptor()

    # Loop through the existing list of users to copy them to the new Security Descriptor
    foreach($wmiAce in $security.Descriptor.DACL) {
        $sd.DACL += $wmiAce
    }
    $sd.Group = $security.Descriptor.Group
    $sd.Owner = $security.Descriptor.Owner

    # Change permissions
    $folder = Get-WmiObject -Class Win32_Directory -Filter "Name='$wmiPath'" -ComputerName $strSvr -Credential $CredR
    $folder.ChangeSecurityPermissions($sd, 4)
    


	
    Invoke-Command -Session $s -ScriptBlock {param($ServerComment,$Port,$Hostname,$Path) New-Website –Name $ServerComment –Port $Port –HostHeader $Hostname –PhysicalPath $Path} -ArgumentList $ServerComment,$Port,$Hostname,$Path
    Invoke-Command -Session $s -ScriptBlock {param($ServerComment,$PoolId) Set-ItemProperty ("IIS:\Sites\" + $ServerComment) -name applicationPool -value $PoolId} -ArgumentList $ServerComment,$PoolId
    Invoke-Command -Session $s -ScriptBlock {param($ServerComment) Set-ItemProperty ("IIS:\Sites\" + $ServerComment) -name ApplicationDefaults.applicationPool -value $ServerComment} -ArgumentList $ServerComment
}


 $RecordSet2
 $counter = 0
 foreach ($Row in $RecordSet2) { 
	 $counter=$counter+1 
	 if ( $counter -eq 1) {continue}
	
	 $Path=$Row.Path.trim()
	 $PoolId=$Row.PoolId.trim()
	 $ServerComment= $Row.ServerComment.trim()
	 $WebsiteId= $Row.WebsiteId.trim()
	 $FullName=@()
	 $FullName= $Row.FullName.trim() -split 'ROOT/'
	 $Name=$FullName[$FullName.Count – 1]

 $pathExt = $Path -replace ':','$'
 $pathS = "\\$strDBServer\$pathExt"
 $pathR = "\\$strSvr\$pathExt"	
 Write-Host "PathS:$pathS"
 Write-Host "PathR:$pathR"	
	
	 Invoke-Command -Session $s -ScriptBlock {param($Path)New-Item -Path $Path -type directory -Force } -ArgumentList $Path
	 New-PSDrive -Name "SOURCE" -PSProvider "FileSystem" -Root $pathS -credential $credS
	 New-PSDrive -Name "DEST" -PSProvider "FileSystem" -Root $pathR -credential $credR
	 Copy-Item "$pathS\*" -Destination $pathR -recurse
	 Remove-PSDrive -Name "SOURCE" -Force
	 Remove-PSDrive -Name "DEST" -Force
     Invoke-Command -Session $s -ScriptBlock {param($ServerComment,$Name,$Path, $PoolId)New-WebApplication –Site $ServerComment –Name $Name –PhysicalPath $Path -ApplicationPool $PoolId -Force} -ArgumentList $ServerComment,$Name,$Path, $PoolId

 }






