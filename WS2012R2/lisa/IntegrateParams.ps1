#######################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#######################################################################

<#
.synopsis
    Update the test parameters in a LISA .xml file and create a new .xml
    with the updated values.

.Description
    The .xml files on the GitHub repository are santized so that they do
    not contain any valid infrasturcture information.  This script will
    dynamically update the test parameters in the specified XML file, and
    write a new .xml file with the updated values.
    
    Dynamically construct a unique name for each test parameter in the Lisa
    test.xml file.  If the unique name is found in the parameterized file,
    then the test parameter value will be updated.  There are three areas
    where test parameters can be defined: Global, Test Case specific, VM
    specific.  The syntax of the unique name will be Area.TestParameterName:

                Global.testParameterName
                TestCaseName.Target_IP
                VMName.SSHKey

    For Global test parameters, the area name "Global" is a constant.  For
    test case specific test params, the "area" is the test case name.  For
    VM specific, the "area" is the VM name.  Hopefully, the following examples
    will eliminate any possible confusion.

    Here is the contents of an example parameterization file that defines what
    should be substituted:
        <parameters>
            <param>Global.GParam2=Global_2</param>
            <param>TestAAA.VMBusVer=2.4</param>
            <param>TestBBB.TC_Count=tc-22</param>
            <param>TestCCC.Target_IP=10.20.30.40</param>
            <param>TestCCC.SSHKey=testCCC_id_rsa</param>
            <param>TestDDD.SSHKey=sles12_id_rsa.ppk</param>
            <param>Sles12Beta9.SSHKey=Nick_id_rsa.ppk</param>
        </parameters>

    Global
        If the <global> section of the Lisa test .xml file has a test parameter
        defined as:
            <param>GParam2=something</param>
        the code will create a unique name of "Global.GParam2" and then look for
        that unique name in the parameterized file.  If this unique name is present
        in the parameterized file, then the value of the global testParam "GParam2"
        will be updated.  After substitution, the updated test param would look like:
            <param>GParam2=Global_2</param>

    Test specific
        When looking for test specific test parameters, the unique will be the
        "test case name"."testParam name"  So if the test named TestAAA has a test
        parameter named VMBusVer, the unique name would be:   TestAAA.VMBusVer

        If this unique name is found in the parameterized file, the value of the
        VMBusVer will be updated.   As an example, if the initial test param definition
        was:
            <param>VMBusVer=xyz</param>

        After substitution (using the above parameterization file), the updated test
        param would look like:
            <param>VMBusVer=2.4</param>

    VM specific
        The behavior here is similar to the test specific behavior. The difference
        is that the vm.Role will be used rather than the test case name. 
        In the <VMs> section of the .xml file, if there is a VM which is defined as SUT1 
        by <Role>, and that VM has another parameter of hvServer, the unique name for hvServer 
        would be:
            SUT1.hvServer

        As an example, if the parameter in the .xml file for the SUT1 VM was：
            <Role>SUT1</Role>
            <hvServer>DefaultServer</hvServer>

        Then the VM hvServer param in the parameterized file would be：
            <param>SUT1.hvServer=LIS-PerfServer</param>
        
        If the VM in the .xml file does not have <Role> defined, this script will treat it 
        as SUT1 by default.

        In the <VMs> section of the .xml file , if there is a param which is defined as VM2NAME
            <param>VM2NAME=something</param>
        the code will create a unique name of "Vm.VM2NAME" and then look for
        that unique name in the parameterized file.  If this unique name is present
        in the parameterized file, then the value of the VMs testParam "VM2NAME"
        will be updated.  After substitution, the updated test param would look like:
            <param>VM2NAME=Version_Client</param>
        
.parameter inputXml
    The input XML file.

.parameter outputXml
    The name of the XML file to create.  This file will have the test parameters
    updated from values in the parameterFile.

.parameter parameterFile
    The parameter file that defines new values to be substituted into the
    output XML file.

.example
    The param can be modified by File and Params
    .\IntegrateParams.ps1 -inputXml xml\myTests.xml -outputXml ~\localizedMyTests.xml -parameterFile ~\myParams.xml
    .\IntegrateParams.ps1 -inputXml xml\myTests.xml -outputXml ~\localizedMyTests.xml -parameterFile "VM2NAME=Version_Client"
#>


param ([String] $inputXml, [String] $outputXml = ".\new.xml", [String] $parameterFile )



#######################################################################
#
# SubstituteParams()
#
#######################################################################
function SubstituteParams( $children, [string] $label)
{
    foreach ($p in $children)
    {
        $fields = $p.InnerText.Split("=")
        if ($fields.Length -ne 2)
        {
            Throw "Error: Invalid test parameter: '$($p.InnerText)'"
        }

        $tpName = $fields[0].Trim()
        $tpValue = $fields[1].Trim()

        $parameterizedName = "${label}.${tpName}"

        if ($params.ContainsKey("$parameterizedName"))
        {
            $newValue = $params[ $parameterizedName ]
            $p.Set_InnerText("${tpName}=${newValue}")
            "${parameterizedName} is set to: ${tpName}=${newValue}"
        }
    }
}

#######################################################################
#
# UpdateParams()
#
#######################################################################
function UpdateParams( $children, [string] $label)
{
    foreach ($p in $children)
    {
        $parameterizedName = "${label}." + $p.Name
        if ($params.ContainsKey("$parameterizedName"))
        {
            $newValue = $params[ $parameterizedName ]
            $p.Set_InnerText("${newValue}")
            "${parameterizedName} is set to: ${newValue}"
        }
    }
}

#######################################################################
#
# ReplaceParameterizedParams()
#
#######################################################################
function ReplaceParameterizedTestParams([String] $paramXmlFile, [System.Xml.XmlDocument] $xmlTests)
{
    $params = @{}
    if (! (test-path $paramXmlFile))
    {
        $params_string = $paramXmlFile.Split(";")
        foreach ($p in $params_string)
        {
            $fields = $p.Split("=")
            if ($fields.Length -ne 2)
            {
                Write-Host "Warn: Invalid parameter syntax: '${p}'.  Ignoring"
                continue
            }

            $params.Add($fields[0].Trim(), $fields[1].Trim())
            
        }
    }
    else
    { 
        $paramData = [xml] (Get-Content -Path $paramXmlFile)
        if ($null -eq $paramData)
        {
            Throw "Error: Unable to parse the parameters .xml file"
        }

    #
    # Put the Parameter data into a hash table
    #
        foreach ($p in $paramDAta.Parameters.param)
        {
            $fields = $p.Split("=")
            if ($fields.Length -ne 2)
            {
                Write-Host "Warn: Invalid parameter syntax: '${p}'.  Ignoring"
                continue
            }

            $params.Add($fields[0].Trim(), $fields[1].Trim())
        }
    }
    #
    # Walk through the global test parameters
    #
    if ($xmlTests.config.global.testParams)
    {
        SubstituteParams $xmlTests.config.global.testParams.childNodes "Global"
    }

    #
    # Walk through the global test parameters
    #
    if ($xmlTests.config.VMs.vm.testParams)
    {
        SubstituteParams $xmlTests.config.VMs.vm.testParams.childNodes "Vm"
    }

    #
    # Walk through each test definition and examine all test params
    #
    foreach ($test in $xmlTests.config.testCases.test)
    {
        if ($test.testParams)
        {
            SubstituteParams $test.testParams.childNodes $test.testName
        }
    }

    #
    # Walk through each VM spceific test param
    #
    foreach ($vm in $xmlTests.config.VMs.vm)
    {
        if (($vm.role -eq $null) -or ($vm.role -eq "") -or ($vm.role.ToUpper() -eq "SUT"))
        {
            $label = "SUT1"
        }
		elseif ($vm.role.ToUpper() -eq "NONSUT")
		{
		    $label = "NonSUT1"
		}
        else
        {
            $label = $vm.role
        }
        UpdateParams $vm.childNodes $label

        if ($vm.hardware)
        {
            UpdateParams $vm.hardware.childNodes "$label.hardware"
        }
    }
}


#######################################################################
#
# Main script body
#
#######################################################################

#
# Load the xml files
#

if (! (test-path $inputXml))
{
    "Error: XML config file '$inputXml' does not exist."
    exit 1
}

if (-not $outputXML)
{
    #
    # Note: There is a default value of ".\new.xml"
    #       so this error should never occur.
    #
    "Error: The outputXML argument was not specified."
    exit 1
}

#if (! (test-path $parameterFile))
#{
#    "Error: The parameterFile '${parameterFile}' does not exist."
#    exit 1
#}

$xmlData = [xml] (Get-Content -Path $inputXml)
if ($null -eq $xmlData)
{
    "Error: Unable to parse the .xml file"
    exit 1
}

#
# A command line specified parameter file takes precedence
# over a parameter file specified in the .xml file.
#
$paramFile = $null

if ($xmlData.Config.Global.ParameterFile)
{
    $paramFile = $xmlData.Config.Global.ParameterFile
}

if ( $parameterFile )
{
    $paramFile = $parameterFile
}

if ($paramFile)
{
    try
    {
        ReplaceParameterizedTestParams $paramFile $xmlData
    }
    catch
    {
        "Error: Unable to integrate test parameters"
        $errMsg = $_.Exception.Message
        "Error: $errMsg"
        exit 1
    }
}
else
{
    "Error: no parameter file specified"
    exit 1
}

#
# Write the modified xml data to the specified file
#
"Write Data to: '${outputXml}'"
$xmlData.Save("$outputXml")
if (-not $?)
{
    "Error: Unable to save xml data to '${outputXml}'"
    exit 1
}

exit 0
