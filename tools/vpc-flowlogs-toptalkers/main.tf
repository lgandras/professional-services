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

module "log_export" {
  for_each               = var.vpc_project_ids
  source                 = "terraform-google-modules/log-export/google"
  destination_uri        = module.destination.destination_uri
  filter                 = "logName=\"projects/${each.value}/logs/compute.googleapis.com%2Fvpc_flows\" jsonPayload.reporter=\"SRC\""
  log_sink_name          = "toptalkers-sink"
  parent_resource_id     = each.value
  parent_resource_type   = "project"
  unique_writer_identity = true
}

module "destination" {
  source                   = "terraform-google-modules/log-export/google//modules/bigquery"
  project_id               = var.logs_project_id
  dataset_name             = var.dataset_name
  location                 = var.location
  log_sink_writer_identity = module.log_export[keys(module.log_export)[0]].writer_identity
}

# copied from terraform-google-modules/log-export/google//modules/bigquery
resource "google_project_iam_member" "bigquery_sink_member" {
  for_each = module.log_export
  project  = var.logs_project_id
  role     = "roles/bigquery.dataEditor"
  member   = each.value.writer_identity
}

locals {
  functions = {
    "IP_FROM_CIDR_STRING" = {
      "definition_body" = "NET.IP_FROM_STRING(SPLIT(cidr, '/')[OFFSET(0)])",
      "arguments" = [
        {"name" = "cidr", "typeKind" = "STRING"},
      ]
    },
    "NET_MASK_FROM_CIDR_STRING" = {
      "definition_body" = "NET.IP_NET_MASK(address_length, CAST(SPLIT(cidr, '/')[OFFSET(1)] AS INT64))",
      "arguments" = [
        {"name" = "cidr", "typeKind" = "STRING"},
        {"name" = "address_length", "typeKind" = "INT64"},
      ]
    },
    "IP_IN_NET" = {
      "definition_body" = "(ip & mask) = (net & mask)",
      "arguments" = [
        {"name" = "ip", "typeKind" = "BYTES"},
        {"name" = "net", "typeKind" = "BYTES"},
        {"name" = "mask", "typeKind" = "BYTES"},
      ]
    },
    "IPBYTES_IN_CIDR" = {
      "definition_body" = trimspace(<<EOF
        `${var.logs_project_id}.${var.dataset_name}.IP_IN_NET`(
          ip,
          `${var.logs_project_id}.${var.dataset_name}.IP_FROM_CIDR_STRING`(
              cidr
          ),
          `${var.logs_project_id}.${var.dataset_name}.NET_MASK_FROM_CIDR_STRING`(
              cidr,
              BYTE_LENGTH(ip)
          )
      )
EOF
      )
      "arguments" = [
        {"name" = "ip", "typeKind" = "BYTES"},
        {"name" = "cidr", "typeKind" = "STRING"},
      ],
      "depends_on" = ["IP_IN_NET", "IP_FROM_CIDR_STRING", "NET_MASK_FROM_CIDR_STRING"]
    },
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
        {"name" = "src_port", "typeKind" = "INT64"},
        {"name" = "dst_port", "typeKind" = "INT64"},
      ]
    },
    "IP_TO_LABEL" = {
      "definition_body" = trimspace(<<EOF
        CASE BYTE_LENGTH(ip)
          WHEN 4 THEN
            CASE
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '35.191.0.0/16') then 'gce-healthcheck'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '130.211.0.0/22') then 'gce-healthcheck'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '209.85.152.0/22') then 'gce-healthcheck'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '209.85.204.0/22') then 'gce-healthcheck'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '64.233.160.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '66.102.0.0/20') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '66.249.80.0/20') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '72.14.192.0/18') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '74.125.0.0/16') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '108.177.8.0/21') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '173.194.0.0/16') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '209.85.128.0/17') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '216.58.192.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '216.239.32.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '172.217.0.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '172.217.32.0/20') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '172.217.128.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '172.217.160.0/20') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '172.217.192.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '108.177.96.0/19') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '35.191.0.0/16') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '130.211.0.0/22') then 'gcp'
              ${join("\n", formatlist("WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '%s') then '%s'", keys(var.ipv4_range_labels), values(var.ipv4_range_labels)))}
              ELSE FORMAT('netaddr4-%s', NET.IP_TO_STRING(ip & NET.IP_NET_MASK(4, ${var.ipv4_aggregate_prefix})))
            END
          WHEN 16 THEN
            CASE
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2001:4860::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2404:6800::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2404:f340::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2600:1900::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2607:f8b0::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2620:11a:a000::/40') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2620:120:e000::/40') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2800:3f0::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2a00:1450::/32') then 'gcp'
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '2c0f:fb50::/32') then 'gcp'
              ${join("\n", formatlist("WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '%s') then '%s'", keys(var.ipv6_range_labels), values(var.ipv6_range_labels)))}
              ELSE FORMAT('netaddr6-%s', NET.IP_TO_STRING(ip & NET.IP_NET_MASK(16, ${var.ipv6_aggregate_prefix})))
            END
          END
EOF
      )
      "arguments" = [
        {"name" = "ip", "typeKind" = "BYTES"},
      ]
      "depends_on" = ["IPBYTES_IN_CIDR"]
    },
    "IP_STRINGS_IN_CIDR" = {
      "definition_body" = trimspace(<<EOF
        `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(NET.IP_FROM_STRING(src_ip), cidr) OR
        `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(NET.IP_FROM_STRING(dest_ip), cidr)
EOF
      )
      "arguments" = [
        {"name" = "src_ip", "typeKind" = "STRING"},
        {"name" = "dest_ip", "typeKind" = "STRING"},
        {"name" = "cidr", "typeKind" = "STRING"},
      ]
      "depends_on" = ["IPBYTES_IN_CIDR"]
    },
    "IP_STRING_TO_LABEL" = {
      "definition_body" = trimspace(<<EOF
        # SUBSTR() is a workaround for b/175366248
        `${var.logs_project_id}.${var.dataset_name}.IP_TO_LABEL`(NET.IP_FROM_STRING(SUBSTR(ip_str, 0, LENGTH(ip_str))))
EOF
      )
      "arguments" = [
        {"name" = "ip_str", "typeKind" = "STRING"},
      ]
      "depends_on" = "IP_TO_LABEL"
    },
    "IP_VERSION" = {
      "definition_body" = "IF(BYTE_LENGTH(NET.IP_FROM_STRING(ip_str)) = 4, 4, 6)"
      "arguments" = [
        {"name" = "ip_str", "typeKind" = "STRING"},
      ]
    },
  }
}

resource "google_bigquery_routine" "functions" {
  for_each     = local.functions
  project      = var.logs_project_id
  dataset_id   = var.dataset_name
  routine_id   = each.key
  language     = "SQL"
  routine_type = "SCALAR_FUNCTION"
  definition_body = each.value["definition_body"]
  dynamic "arguments" {
    for_each  = each.value["arguments"] != null ? each.value["arguments"] : []
    content {
      name      = arguments["value"]["name"]
      data_type = "{\"typeKind\" :  \"${arguments.value.typeKind}\"}"
    }
  }
}

resource "google_bigquery_table" "report" {
  for_each = toset(["day", "week", "month"])
  dataset_id    = var.dataset_name
  friendly_name = "Top Talkers Report"
  table_id      = "top_talkers_report_${each.key}"
  project       = var.logs_project_id
  depends_on    = [module.destination]
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
