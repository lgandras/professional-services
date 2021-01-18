# VPC Flow Logs Analysis 

This solutions allows perform following analysys of the traffic between Google Cloud based projects and on-premises networks.

## Attributing Interconnect or VPN usage to specific service projects in Shared VPC

In case of traffic flowing between the Google Cloud projects and on-premises networks, egress traffic towards on-premises is billed. If that traffic is captured and measured in the [landing zone `interconnect` project (see page 33, "The example.com Dedicated Interconnect connection structure")](https://services.google.com/fh/files/misc/google-cloud-security-foundations-guide.pdf), then the attribution to the service projects will be lost. It is still possible to determine which business unit or team generated the traffic only by inspecting IP ranges of the packets. In case if subnets in the Shared VPC are assigned to multiple service projects (which is a recommended approach to have larger subnets) - it is impossible to distinguish and attribute traffic based only on the IP address. 

To address this limitation the VPC Flow Logs are collected in the Shared VPC host project in each environment, where the full metadata is available. This allows to capture the project_id for the egress traffic, which later can be attributed to the specific business unit or the team. 

To minimize amount and thus costs of the stored logs - only traffic towards the IP ranges of the on-premises networks is captured.

## Deployed resources

* Logs sink and filter (for collecting logs only with traffic sent from the Cloud to on-premises network)
* BigQuery dataset (for storing traffic logs)
* BigQuery view (report)
* BigQuery functions (aggregation and labelling of the addresses/ports for the view)

## Requirements

The following items should be provisioned before spinning up the project:

* An existing project where the [log sink](https://github.com/terraform-google-modules/terraform-google-log-export) will be created.
* An existing project where [BigQuery dataset](https://github.com/terraform-google-modules/terraform-google-log-export/tree/master/modules/bigquery) will be created.
* [VPC flow logs](https://cloud.google.com/vpc/docs/using-flow-logs) must be already enabled in the target subnets where traffic should be monitored.

## Usage

Once installed with the right configuration values, you'll see a view with the name `on_prem_traffic_report` under the newly created dataset. This dataset will automatically get populated by Cloud Operations with the VPC flow logs that are enabled in the project where the log sink resides. It may take some minutes for first entries to appear in the dataset.

## Costs

If you enable VPC flow logs, they will be sent by default to the `_Default` log sink. You can either disable the `_Default` log sink (not recommended) or create an exclusion rule that skips VPC flow logs.
