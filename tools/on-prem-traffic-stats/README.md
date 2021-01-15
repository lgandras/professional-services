# VPC Flowlogs Monitoring

Provides the ability to monitor VPC flowlogs to specific IP address ranges. This allows to example to monitor traffic to on-prem.

## Resources

* Logs sink (for traffic logs)
* BigQuery dataset (for traffic logs)
* BigQuery view (report)
* BigQuery functions (for the view)

## Requirements

The following items should be provisioned before spinning up the project:

* An existing project where the [log sink](https://github.com/terraform-google-modules/terraform-google-log-export) will be created.
* An existing project where [BigQuery dataset](https://github.com/terraform-google-modules/terraform-google-log-export/tree/master/modules/bigquery) will be created.
* [VPC flow logs](https://cloud.google.com/vpc/docs/using-flow-logs) must be already enabled in the target subnets where traffic should be monitored.

## Usage

Once installed with the right configuration values, you'll see a view with the name `on_prem_traffic_report` under the newly created dataset. This dataset will automatically get populated by Cloud Operations with the VPC flow logs that are enabled in the project where the log sink resides.

## Costs

If you enable VPC flow logs, they will be sent by default to the `_Default` log sink. You can either disable the `_Default` log sink (not recommended) or create an exclusion rule that skips VPC flow logs.