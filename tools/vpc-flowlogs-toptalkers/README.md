FIX the TODOS!!!!!

# VPC Flow Logs Top Talkers

This solutions allows to find top-talker subnets or hosts inside the VPC network.

Generated report allows finding top sources of the traffic in a specific VPC.

### The problem

For monitoring reasons it may be necessary to detemrine which hosts or networks in the VPC generate most of the traffic towards other internal hosts or the Internet. While Monitoring dashboards provides ways to do it, they do not distinguish traffic towards Google APIs endpoints and external traffic. 

This solution allows to generate report with desired granulatiry.

## Deployed resources

* Logs sink and filter (for collecting only Egress traffic)
* BigQuery dataset (for storing traffic logs)
* BigQuery view (report)
* BigQuery functions (aggregation and labelling of the addresses/ports for the view)

## Requirements

The following items should be provisioned before spinning up the project:

* An existing project where the [log sink](https://github.com/terraform-google-modules/terraform-google-log-export) will be created.
* An existing project where [BigQuery dataset](https://github.com/terraform-google-modules/terraform-google-log-export/tree/master/modules/bigquery) will be created.
* [VPC flow logs](https://cloud.google.com/vpc/docs/using-flow-logs) must be already enabled in the target subnets where traffic should be monitored.

## Setup

### Google API IP address ranges

The project comes with pre-populated list of IP addresses of Google APIs. Because they may change over the time - there is a scripts in `google-cidrs` directory, which will help to populate the file with updated values. 

### Labelling the traffic

This solution allows adding custome labels to specific ranges and ports. Edit corresponding sections of the `labels.yaml` to add the mapping between the hosts or subnets and text labels.

In case of the traffic on specific port should be highlighted - add it to the list under the `port_labels` key.


### Report settings 

There are several input variables which change report output. They do not affect volume of the logs exported to Big Query.

- `enable_split_by_destination` - set to `false`, if you are interested only in having source IPs in the report
- `enable_split_by_protocol` - set to `false`, if you are not interested in which protocol generated most of the traffic
- `enable_ipv4_traffic` - if set to `false` will exclude all IPv4 traffic from the report.
    - `ipv4_ranges_to_include` `ipv4_ranges_to_exclude` - list of IPs or subnets to include or exclude. Specify single IP in `8.8.8.8/32` form.
    - `ipv4_aggregate_prefix` - if the subnet is not mentioned in `labels.yaml`, then at which granularity level aggregate traffic together. I.e. when it is `24`, all IPs in `10.0.0.0/24` network will be labelled `TODO-nnnnnnn`. If you want to see per-hosts statistics, please use `32` as a value.
- `enable_ipv6_traffic` - same as above, but for `IPv6` traffic
    - `ipv6_ranges_to_include`
    - `ipv6_ranges_to_exclude`
    - `ipv6_aggregate_prefix`


### Time ranges
 
Please note that the `current_month_*` and `last_month_*` reports will process only the tables from the corresponding time ranges. If you need historical time ranges - please change the view implementation.

## Usage

Once installed with the right configuration values, you'll see several views with the names `report` under the newly created dataset. This dataset will automatically get populated by Cloud Operations with the VPC flow logs that are enabled in the project where the log sink resides. It may take some minutes for first entries to appear in the dataset.

## Costs

If you enable VPC flow logs, they will be sent by default to the `_Default` log sink. You can either disable the `_Default` log sink (not recommended) or create an exclusion rule that skips VPC flow logs.