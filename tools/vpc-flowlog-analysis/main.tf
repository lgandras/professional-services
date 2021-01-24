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
  filter                 = <<EOT
  logName="projects/${var.vpc_project_id}/logs/compute.googleapis.com%2Fvpc_flows" jsonPayload.reporter="SRC"
      (${join(" OR ", formatlist("ip_in_net(jsonPayload.connection.dest_ip, \"%s\")", var.include_interconnect_ip_ranges))})
  %{if 0 < length(var.exclude_interconnect_ip_ranges)}
  NOT (${join(" OR ", formatlist("ip_in_net(jsonPayload.connection.dest_ip, \"%s\")", var.exclude_interconnect_ip_ranges))})
  %{endif}
EOT
  log_sink_name          = "tf-sink"
  parent_resource_id     = var.vpc_project_id
  parent_resource_type   = "project"
  unique_writer_identity = true
}

module "destination" {
  source                   = "terraform-google-modules/log-export/google//modules/bigquery"
  project_id               = var.logs_project_id
  dataset_name             = var.dataset_name
  location                 = var.location
  log_sink_writer_identity = module.log_export.writer_identity
}

locals {
  routines = {
    "PORTS_TO_PROTO" = {
      "definition_body" = trimspace(<<EOF
        CASE
          WHEN src_port = 22 OR dst_port = 22 then 'ssh'
          WHEN src_port = 80 OR dst_port = 80 then 'http'
          WHEN src_port = 443 OR dst_port = 443 then 'https'
          WHEN src_port = 10402 OR dst_port = 10402 then 'gae' -- AppEngine Flex
          WHEN src_port = 8443 OR dst_port = 8443 then 'gae' -- AppEngine Flex
          ELSE FORMAT('other-%d->%d', src_port, dst_port)
        END
EOF
      )
      "arguments" = [
        { "name" = "src_port", "typeKind" = "INT64" },
        { "name" = "dst_port", "typeKind" = "INT64" },
      ]
    },
  }
}

resource "google_bigquery_routine" "main" {
  for_each        = local.routines
  project         = var.logs_project_id
  dataset_id      = var.dataset_name
  routine_id      = each.key
  language        = "SQL"
  routine_type    = "SCALAR_FUNCTION"
  definition_body = each.value["definition_body"]
  dynamic "arguments" {
    for_each = each.value["arguments"] != null ? each.value["arguments"] : []
    content {
      name      = arguments["value"]["name"]
      data_type = "{\"typeKind\" :  \"${arguments.value.typeKind}\"}"
    }
  }
}

resource "google_bigquery_table" "main" {
  dataset_id    = var.dataset_name
  friendly_name = "On-Prem Traffic Report"
  table_id      = "on_prem_traffic_report"
  project       = var.logs_project_id

  view {
    query = trimspace(<<EOF
SELECT 
  DATE_TRUNC(PARSE_DATE('%F', SPLIT(jsonPayload.start_time, 'T')[OFFSET(0)]), WEEK) as day,
  `${var.logs_project_id}.${var.dataset_name}.PORTS_TO_PROTO`(
    CAST(jsonPayload.connection.src_port as INT64), 
    CAST(jsonPayload.connection.dest_port as INT64)
  ) as protocol,
  SUM(CAST(jsonPayload.bytes_sent as int64)) as bytes,
  SUM(CAST(jsonPayload.packets_sent as int64)) as packets,
  jsonPayload.src_instance.project_id as src_project_id

FROM `${var.logs_project_id}.${var.dataset_name}.compute_googleapis_com_vpc_flows_*`

GROUP BY
day, protocol, src_project_id
ORDER BY packets DESC

EOF
    )
    use_legacy_sql = false
  }
}
