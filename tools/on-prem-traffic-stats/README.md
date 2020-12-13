# VPC Flowlogs Monitoring

Provides the ability to monitor VPC flowlogs to specific IP address ranges. This allows to example to monitor traffic to on-prem.

## Resources

* Logs sink
* BigQuery dataset
* BigQuery job

## Limitations

Right now, saved queries can [only be created via the UI](https://cloud.google.com/bigquery/docs/saving-sharing-queries). Right after spinning up the module, you'll have to:

1. Click in *Job History*
2. Choose the latest job executed. This one starts with `CREATE TEMP FUNCTION` and it will contain the IP address ranges specified in the configuration.
3. Click on *Open query in editor*
4. Click on *Save > Save Query*

This will allow you to execute this query afterwards directly via the console.
