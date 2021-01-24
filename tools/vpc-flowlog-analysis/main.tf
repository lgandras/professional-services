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
  location                 = var.location
  log_sink_writer_identity = module.log_export.writer_identity
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
      ]
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
              -- add custom labels for on-premises networks
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, '${var.on_prem_ip_range}') then 'on-prem-system1'
              ELSE FORMAT('netaddr4-%s', NET.IP_TO_STRING(ip & NET.IP_NET_MASK(4, ${var.ipv4_prefix})))
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
              -- add custom labels for on-premises networks
              WHEN `${var.logs_project_id}.${var.dataset_name}.IPBYTES_IN_CIDR`(ip, 'fd00::/8') then 'on-prem-system1'
              ELSE FORMAT('netaddr6-%s', NET.IP_TO_STRING(ip & NET.IP_NET_MASK(16, ${var.ipv6_prefix})))
            END
          END
EOF
      )
      "arguments" = [
        {"name" = "ip", "typeKind" = "BYTES"},
      ]
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
  dataset_id    = var.dataset_name
  friendly_name = "On-Prem Traffic Report"
  table_id      = "on_prem_traffic_report"
  project       = var.logs_project_id

  view {
    query          = trimspace(<<EOF
SELECT
  `${var.logs_project_id}.${var.dataset_name}.IP_STRING_TO_LABEL`(jsonPayload.connection.src_ip) AS src,
  `${var.logs_project_id}.${var.dataset_name}.IP_STRING_TO_LABEL`(jsonPayload.connection.dest_ip) AS dest,
  DATE_TRUNC(PARSE_DATE('%F', SPLIT(jsonPayload.start_time, 'T')[OFFSET(0)]), WEEK) as day,
  -- MIN(jsonPayload.src_vpc.vpc_name) as src_vpc,
  -- MIN(jsonPayload.dest_vpc.vpc_name) as dest_vpc,
  `${var.logs_project_id}.${var.dataset_name}.PORTS_TO_PROTO`(
    CAST(jsonPayload.connection.src_port as INT64),
    CAST(jsonPayload.connection.dest_port as INT64)) as protocol,
  SUM(CAST(jsonPayload.bytes_sent as int64)) as bytes,
  SUM(CAST(jsonPayload.packets_sent as int64)) as packets,
  `${var.logs_project_id}.${var.dataset_name}.IP_VERSION`(jsonPayload.connection.src_ip) as ip_version

FROM `${var.logs_project_id}.${var.dataset_name}.compute_googleapis_com_vpc_flows_*`

GROUP BY src, dest, ip_version, day, protocol

EOF
    )
    use_legacy_sql = false
  }
}
