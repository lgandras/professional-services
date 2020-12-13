/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module "log_export" {
  source                 = "terraform-google-modules/log-export/google"
  destination_uri        = module.destination.destination_uri
  filter                 = "logName=\"projects/${var.vpc_project_id}/logs/compute.googleapis.com%2Fvpc_flows\" jsonPayload.reporter=\"SRC\" (ip_in_net(jsonPayload.connection.dest_ip, \"${var.on_prem_ip_range}\"))"
  log_sink_name          = "tf-sink"
  parent_resource_id     = var.vpc_project_id
  parent_resource_type   = "project"
  unique_writer_identity = true
}

module "destination" {
  source                   = "terraform-google-modules/log-export/google//modules/bigquery"
  project_id               = var.logs_project_id
  dataset_name             = var.dataset_name
  location                 = "EU"
  log_sink_writer_identity = module.log_export.writer_identity
}

data "template_file" "bigquery_view" {
  template = file("${path.module}/query.sql")
  vars = {
    on_prem_ip_range = var.on_prem_ip_range
    logs_project_id  = var.logs_project_id
    dataset_name     = var.dataset_name
  }
}

# for now saving queries is only possible via the console: https://cloud.google.com/bigquery/docs/saving-sharing-queries
resource "google_bigquery_job" "job" {
  project  = var.logs_project_id
  job_id   = "vpc_flowlogs"
  location = "EU"

  query {
    query = data.template_file.bigquery_view.rendered

    allow_large_results = true
    flatten_results = true

    script_options {
      key_result_statement = "LAST"
    }
  }
}