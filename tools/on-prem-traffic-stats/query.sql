CREATE TEMP FUNCTION
    IP_FROM_CIDR_STRING(cidr STRING)
    AS (
        NET.IP_FROM_STRING(SPLIT(cidr, '/')[OFFSET(0)])
    )
;

CREATE TEMP FUNCTION
    NET_MASK_FROM_CIDR_STRING(cidr STRING)
    AS (
        NET.IP_NET_MASK(4, CAST(SPLIT(cidr, '/')[OFFSET(1)] AS INT64))
    )
;

CREATE TEMP FUNCTION
    IP_IN_NET(ip BYTES, net BYTES, mask BYTES)
    AS (
        (ip & mask) = (net & mask)
    )
;

CREATE TEMP FUNCTION
    IPBYTES_IN_CIDR(ip BYTES, cidr STRING)
    AS (
        IP_IN_NET(
            ip,
            IP_FROM_CIDR_STRING(
                cidr
            ),
            NET_MASK_FROM_CIDR_STRING(
                cidr
            )
        )
    )
;

CREATE TEMP FUNCTION IP_TO_LABEL(ip BYTES, aggregate_prefix INT64)
  as (
  case 
  when IPBYTES_IN_CIDR(ip, '35.191.0.0/16') then 'gce-healthcheck'
  when IPBYTES_IN_CIDR(ip, '130.211.0.0/22') then 'gce-healthcheck'
  when IPBYTES_IN_CIDR(ip, '209.85.152.0/22') then 'gce-healthcheck'
  when IPBYTES_IN_CIDR(ip, '209.85.204.0/22') then 'gce-healthcheck'
  when IPBYTES_IN_CIDR(ip, '64.233.160.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '66.102.0.0/20') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '66.249.80.0/20') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '72.14.192.0/18') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '74.125.0.0/16') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '108.177.8.0/21') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '173.194.0.0/16') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '209.85.128.0/17') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '216.58.192.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '216.239.32.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '172.217.0.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '172.217.32.0/20') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '172.217.128.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '172.217.160.0/20') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '172.217.192.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '108.177.96.0/19') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '35.191.0.0/16') then 'gcp'
  when IPBYTES_IN_CIDR(ip, '130.211.0.0/22') then 'gcp'
  -- add custom labels
  when IPBYTES_IN_CIDR(ip, '${on_prem_ip_range}') then 'on-prem-system1'
  else
      FORMAT('netaddr-%s', NET.IP_TO_STRING(ip & NET.IP_NET_MASK(4, aggregate_prefix)))
     end
  );

CREATE TEMP FUNCTION IP_STRINGS_IN_CIDR(src_ip STRING, dest_ip STRING, cidr STRING) AS (
  IPBYTES_IN_CIDR(NET.IP_FROM_STRING(src_ip), cidr) OR 
  IPBYTES_IN_CIDR(NET.IP_FROM_STRING(dest_ip), cidr) 
);

CREATE TEMP FUNCTION PORTS_TO_PROTO(src_port INT64, dst_port INT64)
  as (
  case 
  when src_port = 22 OR dst_port = 22 then 'ssh'
    when src_port = 80 OR dst_port = 80 then 'http'
    when src_port = 443 OR dst_port = 443 then 'https'
    when src_port = 10402 OR dst_port = 10402 then 'gae' -- AppEngine Flex
    when src_port = 8443 OR dst_port = 8443 then 'gae' -- AppEngine Flex
  else
      FORMAT('other-%d->%d', src_port, dst_port)
     end
  );

SELECT 
  DATE_TRUNC(PARSE_DATE('%F', SPLIT(jsonPayload.start_time, 'T')[OFFSET(0)]), WEEK) as day,
  PORTS_TO_PROTO(
    CAST(jsonPayload.connection.src_port as INT64), 
    CAST(jsonPayload.connection.dest_port as INT64)
  ) as protocol,
  SUM(CAST(jsonPayload.bytes_sent as int64)) as bytes,
  SUM(CAST(jsonPayload.packets_sent as int64)) as packets,
  jsonPayload.src_instance.project_id as src_project_id

FROM `${logs_project_id}.${dataset_name}.compute_googleapis_com_vpc_flows_*`

GROUP BY
day, protocol, src_project_id
ORDER BY packets DESC
