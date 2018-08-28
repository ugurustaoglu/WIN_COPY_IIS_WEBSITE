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
$SqlConnection.ConnectionString = "Server = $SQLServer; Database = $DATABASE;User ID = $uid; Password = $pwd;"
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.CommandText = $SqlQuery
$SqlCmd.Connection = $SqlConnection
$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$SqlAdapter.SelectCommand = $SqlCmd
$DataSet = New-Object System.Data.DataSet
$SqlAdapter.Fill($DataSet)
$SqlConnection.Close()
Return $DataSet.Tables[0]

}

$Username = 'USERNAMEOFDESTINATIONSERVERWHEREYOUCREATETHEAPPPOOL'
$Password = 'PASSWORDOFDESTINATIONSERVERWHEREYOUCREATETHEAPPPOOL'
$strDBServer ='SERVERWHEREYOUCOPYTHEAPPPOOLFROM'
$strSvr = 'DESTINATIONSERVERWHEREYOUCREATETHEAPPPOOL'
$pass = ConvertTo-SecureString -AsPlainText $Password -Force
$Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$pass




$RecordSet = Invoke-SQL -sqlQuery "select * from AppPools where ServerName='$strDBServer'"

$s = New-PSSession -ComputerName $strSvr  -credential $Cred
$counter = 0;
foreach ($Row in $RecordSet) { 
	$counter=$counter+1 
	if ( $counter -eq 1) {continue}
	$arr = $Row.Name -split '/'
#	$strName=$arr[2] -replace '\s',''
	$strName=$arr[2].trim()
	write-Output $strName
	$idType=$Row.AppPoolIdentityType
	$strUsr= $Row.WAMUserName
	$strPass= $Row.WAMUserPass
	$managedPipelineMode=[int]$Row.ManagedPipelineMode		#0 - Integrated #1 - Classic
	$managedRuntimeVersion=$Row.ManagedRuntimeVersion   #"v4.0" #"v2.0"  #"No Managed Code"
	$PeriodicRestartSchedule=$Row.PeriodicRestartSchedule.trim()
#	write-Output $Row.PeriodicRestartSchedule
	$restartTimes=@()
	if ($PeriodicRestartSchedule -ne "") {
		$restartTimes = $PeriodicRestartSchedule -split ','
	}
		write-Output @($restartTimes).Count
		write-Output $restartTimes 
#        SetScript = ({ 
#            Set-ItemProperty "IIS:\AppPools\{0}" "managedRuntimeVersion" "v4.0"
#            Set-ItemProperty "IIS:\AppPools\{0}" "managedPipelineMode" 1 # 0 = Integrated, 1 = Classic
#        } -f @($ApplicationPoolName))


	Invoke-Command -Session $s -ScriptBlock {param($strName) New-WebAppPool -force -Name $strName} -ArgumentList $strName
	Invoke-Command -Session $s -ScriptBlock {param($strName,$idType) Set-ItemProperty "IIS:\AppPools\$strName" processModel.identityType $idType} -ArgumentList $strName,$idType
	Invoke-Command -Session $s -ScriptBlock {param($strName,$strUsr) Set-ItemProperty "IIS:\AppPools\$strName" processModel.username $strUsr } -ArgumentList $strName,$strUsr
	Invoke-Command -Session $s -ScriptBlock {param($strName,$strPass) Set-ItemProperty "IIS:\AppPools\$strName" processModel.password $strPass } -ArgumentList $strName,$strPass
	Invoke-Command -Session $s -ScriptBlock {param($strName,$managedPipelineMode) Set-ItemProperty "IIS:\AppPools\$strName" "managedPipelineMode" $managedPipelineMode} -ArgumentList $strName,$managedPipelineMode
	Invoke-Command -Session $s -ScriptBlock {param($strName,$managedRuntimeVersion) Set-ItemProperty "IIS:\AppPools\$strName" "managedRuntimeVersion" $managedRuntimeVersion} -ArgumentList $strName,$managedRuntimeVersion
	Invoke-Command -Session $s -ScriptBlock {param($strName) Clear-ItemProperty "IIS:\AppPools\$strName" "Recycling.periodicRestart.schedule"} -ArgumentList $strName
	Invoke-Command -Session $s -ScriptBlock {param($strName) Start-WebAppPool -Name $strName} -ArgumentList $strName

#	Clear-ItemProperty IIS:\AppPools\$ApplicationPoolName -Name Recycling.periodicRestart.schedule

	foreach ($restartTime in $restartTimes) {
		$i=$i+1
		if ($i=1) {
			Invoke-Command -Session $s -ScriptBlock {param($strName,$restartTime) Set-ItemProperty "IIS:\AppPools\$strName" "Recycling.periodicRestart.schedule" @{value=$restartTime}} -ArgumentList $strName,$restartTime
		}
		else	{
			Invoke-Command -Session $s -ScriptBlock {param($strName,$restartTime) New-ItemProperty "IIS:\AppPools\$strName" "Recycling.periodicRestart.schedule" @{value=$restartTime}} -ArgumentList $strName,$restartTime
		}
    } 
	
}



Disconnect-PSSession($s)
Exit-PSSession







