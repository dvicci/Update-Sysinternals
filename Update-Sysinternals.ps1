$inputXML = @"
<Window x:Class="WpfApp1.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:WpfApp1"
        mc:Ignorable="d"
        Title="Update Sysinternal Tools" Width="640" Height="480">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="274*"/>
            <ColumnDefinition Width="36*"/>
            <ColumnDefinition Width="207*"/>
        </Grid.ColumnDefinitions>
        <Button Name="Button_SelectFolder" Content="Select Folder..." Margin="10,0,0,10" Height="20" VerticalAlignment="Bottom" HorizontalAlignment="Left" Width="124" IsDefault="True"/>
        <Button Name="Button_UpdateTools" Content="Update Tools..." Margin="139,0,0,10" IsEnabled="False" Height="20" VerticalAlignment="Bottom" HorizontalAlignment="Left" Width="186"/>
        <ListView Name="ListView_UpdateInformation" Margin="10,42,10,35" Grid.ColumnSpan="3">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Filename" DisplayMemberBinding ="{Binding 'Filename'}" Width="175"/>
                    <GridViewColumn Header="Local File Date" DisplayMemberBinding ="{Binding 'Local File Date'}" Width="130"/>
                    <GridViewColumn Header="Remote File Date" DisplayMemberBinding ="{Binding 'Remote File Date'}" Width="130"/>
                    <GridViewColumn Header="Updated" DisplayMemberBinding ="{Binding 'Updated'}" Width="175"/>
                </GridView>
            </ListView.View>
        </ListView>
        <Button Content="Cancel" Grid.Column="2" Margin="0,0,90,10" IsCancel="True" Height="20" VerticalAlignment="Bottom" HorizontalAlignment="Right" Width="75"/>
        <Label Name="WorkingDirectory" Content="Select a folder using the 'Select Folder...' button below..." Margin="10,10,10,0" VerticalAlignment="Top" Grid.ColumnSpan="3" Height="27" Background="#FFE0DFDF"/>
        <Button Name="Button_Ok" Content="Ok" Grid.Column="2" Margin="0,0,10,10" HorizontalAlignment="Right" Width="75" Height="20" VerticalAlignment="Bottom"/>
    </Grid>
</Window>
"@
 
$inputXML = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window'
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML

$reader=(New-Object System.Xml.XmlNodeReader $xaml) 
try { $Form=[Windows.Markup.XamlReader]::Load( $reader ) }
catch [System.Management.Automation.MethodInvocationException] {
    Write-Warning "We ran into a problem with the XAML code.  Check the syntax for this control..."
    write-host $error[0].Exception.Message -ForegroundColor Red
    if ($error[0].Exception.Message -like "*button*") {
        write-warning "Ensure your &lt;button in the `$inputXML does NOT have a Click=ButtonClick property.  PS can't handle this`n`n`n`n"
    }
}
catch {
    Write-Host "Unable to load Windows.Markup.XamlReader. Double-check syntax and ensure .net is installed."
}
 
$xaml.SelectNodes("//*[@Name]") | ForEach-Object {Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)}

<#
Function Get-FormVariables {
    if ($global:ReadmeDisplay -ne $true) {
        Write-host "If you need to reference this display again, run Get-FormVariables" -ForegroundColor Yellow;$global:ReadmeDisplay=$true
    }
    get-variable WPF*
}
Get-FormVariables
#>

Function GetFolder() {
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{}
    [void]$FolderBrowser.ShowDialog()
    $FolderBrowser.SelectedPath
}

Function UpdateSysinternalsHTTP ([string]$ToolsLocalDir, [string]$ToolsURL) {
    BEGIN { 
        $wc = new-object System.Net.WebClient
        $userAgent = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.2;)"
        $wc.Headers.Add("user-agent", $userAgent)
        $ToolsBlock = "<pre>.*</pre>"
        $WebPageCulture = New-Object System.Globalization.CultureInfo("en-us")
    }
    PROCESS {
        $Tools = @{}
        $ToolsPage = $wc.DownloadString($ToolsUrl)
        $matchers = [string] $ToolsPage | Select-String -pattern  "$ToolsBlock" -AllMatches
        ForEach ($match in $matchers.Matches) {
            $txt = ( ($match.Value  -replace "</A><br>", "`r`n") -replace  "<[^>]*?>","")
            ForEach ($lines in $txt -Split "`r`n") {
                $line = $lines | Select-String  -NotMatch -Pattern "To Parent|^$|&lt;dir&gt;"
                if ($line) {
                    $line = $line.toString().Trim(' ')
                    $line = $line -replace '\s+', ' '
                    $lineArray = $line -Split "\s"
                    $date = $lineArray[0] + " " + $lineArray[1] + " " + $lineArray[2] + " " + $lineArray[3] + " " + $lineArray[4] + " " + $lineArray[5]
                    $date = [DateTime]::ParseExact($date, 'dddd, MMMM d, yyyy h:mm tt',$null)
                    $file = $lineArray[7]
                    $Tools["$file"] = $date
                }
            }
        }
        if (Test-Path $ToolsLocalDir) {
            $DebugPreference = "SilentlyContinue"
            ForEach ($file in $Tools.Keys.GetEnumerator())  {
                if ($file -Like "*.sys") { continue }
                if ($file -Like "*.CNT") { continue }
                $NeedUpdate = $null
                $LocalFileDate_raw = $null
                $LocalFileDate = $null
                $RemoteFileDate = ($tools["$file"]).ToUniversalTime()
                $FilePath = "$script:ToolsLocalDir\$file"
                if (Test-Path $FilePath) {
                    $SubtractSeconds = New-Object System.TimeSpan 0, 0, 0, ((Get-ChildItem $FilePath).lastWriteTime).second, 0
                    $LocalFileDate_raw = ((Get-ChildItem $FilePath).lastWriteTime).Subtract($SubtractSeconds)
                    $LocalFileDate = ($LocalFileDate_raw.ToUniversalTime())
                    if ($LocalFileDate -lt $RemoteFileDate) { $NeedUpdate = $true }
                } else {
                    $NeedUpdate = $true
                }
                if ($NeedUpdate) {
                    Try {
                        $wc.DownloadFile("$ToolsUrl/$file","$FilePath")
                        $f = Get-ChildItem "$FilePath"
                        $f.lastWriteTime = ($tools["$file"])
                    } catch [Net.WebException] {
                        $NeedUpdate = "$_.Exception"
                    }
                }
                $WPFListView_UpdateInformation.Items.Add([pscustomobject]@{'Filename'=$file;'Local File Date'=$LocalFileDate;'Remote File Date'=$RemoteFileDate;'Updated'=$NeedUpdate})
                [System.Windows.Forms.Application]::DoEvents() # Refresh the lsitview container
            }
        }
    }
    END {
        $wc.Close
        $WPFWorkingDirectory.Content = "All done!  Click 'Cancel' or 'OK' to exit."
    }
}

$AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12,Tls13'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

$WPFButton_SelectFolder.Add_Click({
    $script:ToolsLocalDir = GetFolder
    if ($script:ToolsLocalDir -ne "") {
        $WPFWorkingDirectory.Content = "Click the 'Update $script:ToolsLocalDir ...' button below to begin."
        $WPFButton_UpdateTools.Content = "Update $script:ToolsLocalDir ..."
        $WPFButton_UpdateTools.IsEnabled = $true
    }
})

$WPFButton_UpdateTools.Add_Click({
    $ToolsUrl = "https://live.sysinternals.com"
    UpdateSysinternalsHTTP -ToolsLocalDir $script:ToolsLocalDir -ToolsURL $ToolsURL
})

$WPFButton_OK.Add_Click({
    $Form.Close()
})

$Form.ShowDialog() | out-null
