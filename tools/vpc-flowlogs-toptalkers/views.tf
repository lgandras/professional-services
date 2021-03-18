/**
 * Copyright 2021 Google LLC
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

locals {
  ipv4_include_text = trimspace(<<EOT
  %{if var.enable_ipv4_traffic}
    %{if 0 < length(var.ipv4_ranges_to_include)}
      include ${join(", ", var.ipv4_ranges_to_include)} IP address ranges ${local.ipv4_except_text}
    %{else}
      include all IP address ranges ${local.ipv4_except_text}
    %{endif}
  %{else}
    not include any ranges
  %{endif}
EOT
    )
  ipv4_except_text = trimspace(<<EOT
    %{if 0 < length(var.ipv4_ranges_to_exclude)}
      except ${join(", ", var.ipv4_ranges_to_exclude)}
    %{endif}
EOT
    )

  ipv6_include_text = trimspace(<<EOT
  %{if var.enable_ipv6_traffic}
    %{if 0 < length(var.ipv6_ranges_to_include)}
      include ${join(", ", var.ipv6_ranges_to_include)} IP address ranges ${local.ipv6_except_text}
    %{else}
      include all IP address ranges ${local.ipv6_except_text}
    %{endif}
  %{else}
    not include any ranges
  %{endif}
EOT
    )
  ipv6_except_text = trimspace(<<EOT
    %{if 0 < length(var.ipv6_ranges_to_exclude)}
      except ${join(", ", var.ipv6_ranges_to_exclude)}
    %{endif}
EOT
    )

  ipv4_filter = <<EOT
  %{if var.enable_ipv4_traffic}
    TRUE
    %{if 0 < length(var.ipv4_ranges_to_include)}
      AND (${join(" OR ", formatlist("IP_STRINGS_IN_CIDR(jsonPayload.connection.src_ip, jsonPayload.connection.dest_ip, '%s')", var.ipv4_ranges_to_include))})
    %{endif}
    %{if 0 < length(var.ipv4_ranges_to_exclude)}
      AND NOT (${join(" OR ", formatlist("IP_STRINGS_IN_CIDR(jsonPayload.connection.src_ip, jsonPayload.connection.dest_ip, '%s')", var.ipv4_ranges_to_exclude))})
    %{endif}
  %{else}
    FALSE
  %{endif}

EOT
  ipv6_filter = <<EOT
  %{if var.enable_ipv6_traffic}
    TRUE
    %{if 0 < length(var.ipv6_ranges_to_include)}
      AND (${join(" OR ", formatlist("IP_STRINGS_IN_CIDR(jsonPayload.connection.src_ip, jsonPayload.connection.dest_ip, '%s')", var.ipv6_ranges_to_include))})
    %{endif}
    %{if 0 < length(var.ipv6_ranges_to_exclude)}
      AND NOT (${join(" OR ", formatlist("IP_STRINGS_IN_CIDR(jsonPayload.connection.src_ip, jsonPayload.connection.dest_ip, '%s')", var.ipv6_ranges_to_exclude))})
    %{endif}
  %{else}
    FALSE
  %{endif}
EOT

  group_by = join(", ", concat(
    ["src"],
    var.enable_split_by_destination ? ["dest"] : [],
    ["ip_version", "time_period"],
    var.enable_split_by_protocol ? ["protocol"] : []
  ))
}


resource "google_bigquery_table" "report" {
  for_each = toset(["day", "week", "month"])
  dataset_id    = var.dataset_name
  friendly_name = "Top Talkers Report"
  table_id      = "top_talkers_report_${each.key}"
  project       = var.logs_project_id
  depends_on    = [
    module.destination,
    google_bigquery_routine.IP_STRING_TO_LABEL,
    google_bigquery_routine.PORTS_TO_PROTO,
    google_bigquery_routine.IP_VERSION
  ]
  description   = <<EOT
  Regarding IPv4, the report will ${local.ipv4_include_text}.
  Regarding IPv6, the report will ${local.ipv6_include_text}.
EOT

  view {
    query          = trimspace(<<EOF
SELECT
  DATE_TRUNC(PARSE_DATE('%F', SPLIT(jsonPayload.start_time, 'T')[OFFSET(0)]), `${each.key}`) as time_period,
  `${var.logs_project_id}.${var.dataset_name}.IP_STRING_TO_LABEL`(jsonPayload.connection.src_ip) AS src,
  `${var.logs_project_id}.${var.dataset_name}.IP_STRING_TO_LABEL`(jsonPayload.connection.dest_ip) AS dest,
  MIN(jsonPayload.src_vpc.vpc_name) as src_vpc,
  MIN(jsonPayload.dest_vpc.vpc_name) as dest_vpc,
  `${var.logs_project_id}.${var.dataset_name}.PORTS_TO_PROTO`(
    CAST(jsonPayload.connection.src_port as INT64),
    CAST(jsonPayload.connection.dest_port as INT64)) as protocol,
  SUM(CAST(jsonPayload.bytes_sent as int64)) as bytes,
  SUM(CAST(jsonPayload.packets_sent as int64)) as packets,
  `${var.logs_project_id}.${var.dataset_name}.IP_VERSION`(jsonPayload.connection.src_ip) as ip_version

FROM `${var.logs_project_id}.${var.dataset_name}.compute_googleapis_com_vpc_flows_*`

WHERE IF(`${var.logs_project_id}.${var.dataset_name}.IP_VERSION`(jsonPayload.connection.src_ip) = 4, ${local.ipv4_filter}, ${local.ipv6_filter})

GROUP BY ${local.group_by}

EOF
    )
    use_legacy_sql = false
  }
}
