# Big-IP F5 Local Traffic Manager VSTS release tasks
Tasks for manipulating F5 nodes and pool members.

These tasks require REST API connectivity to a Big-IP F5 v11.5.1 Build 8.0.175 Hotfix 8 or later device.  Typically, that necessitates the use of an [on-premises build agent](https://www.visualstudio.com/en-us/docs/build/admin/agents/v2-windows).  Although, a hosted build is possible if you are willing to expose your F5 device to the internet (not recommended).

## Tasks
1. **Disable - Node**

   This task `disables` node(s) by name.

1. **Disable - Pool Member**

   This task `disables` pool member(s) identified by a pool name and member name regular expression.

1. **Enable - Node**

   This task `enables` node(s) by name.

1. **Enable - Pool Member**
    
   This task `enables` pool member(s) identified by a pool name and member name regular expression.

1. **Blue-Green Deployment - Selection**

   This task facilitates [blue-green deployments](https://martinfowler.com/bliki/BlueGreenDeployment.html).  You specify a virtual server and 2 pool names.  The pool members will be identified and validated then the idle pool's members will be output to $(F5MachineList) and $(F5ServerList) environment variables for use in subsequent tasks.  It is intended to be paired with a subsequent 'Blue-Green Deployment - Swap' task which will swap the virtual server's active pool based on the output of this task.

1. **Blue-Green Deployment - Swap**

   This task commits blue-green swaps initiated by 1 or more 'Blue-Green Deployment - Selection' tasks.  Pool(s) that are determined to be idle at selection time will be activated - this should help mitigate risks resulting from the use of otherwise redundant Blue-Green Deployment tasks.  This should be the last (and only Swap) task for each environment in a release definition.  And, it is highly recommended that the Swap task follow a manual intervention server task to allow the newly deployed environment to be tested prior to the final cut-over.
       
> WARNING: Each Blue-Green Deployment - Selection task writes an xml file to the $Env:SYSTEM_WORKFOLDER.  The Blue-Green Deployment - Swap task will not be able to locate the file(s) if executed by an agent running on a different server or configured for a different _work directory.  If this occurs, the swap task will fail.  I am considering using the (ExtensionDataService)[https://www.visualstudio.com/en-us/docs/integrate/extensions/reference/client/api/vss/sdk/services/extensiondata/extensiondataservice], but it would require all involved run agent's ~Allow scripts to access OAuth token~ option to be checked.  Alternative suggestions are welcome.