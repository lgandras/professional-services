#!/usr/bin/env python3

import json
import netaddr
import urllib.request

goog_url="https://www.gstatic.com/ipranges/goog.json"
cloud_url="https://www.gstatic.com/ipranges/cloud.json"

def read_url(url):
   try:
      s = urllib.request.urlopen(url).read()
      return json.loads(s)
   except urllib.error.HTTPError:
      print("Invalid HTTP response from %s" % url)
      return {}
   except json.decoder.JSONDecodeError:
      print("Could not parse HTTP response from %s" % url)
      return {}

def main():
   goog_json=read_url(goog_url)
   cloud_json=read_url(cloud_url)

   if goog_json and cloud_json:
      print("# Please use update-google-cidrs.sh to update this file.")
      print("# {} published: {}".format(goog_url,goog_json.get('creationTime')))
      print("# {} published: {}".format(cloud_url,cloud_json.get('creationTime')))
      goog_ipv4_cidrs = netaddr.IPSet()
      goog_ipv6_cidrs = netaddr.IPSet()
      for e in goog_json['prefixes']:
         if e.get('ipv4Prefix'):
            goog_ipv4_cidrs.add(e.get('ipv4Prefix'))
         if e.get('ipv6Prefix'):
            goog_ipv6_cidrs.add(e.get('ipv6Prefix'))
      cloud_ipv4_cidrs = netaddr.IPSet()
      cloud_ipv6_cidrs = netaddr.IPSet()
      for e in cloud_json['prefixes']:
         if e.get('ipv4Prefix'):
            cloud_ipv4_cidrs.add(e.get('ipv4Prefix'))
         if e.get('ipv6Prefix'):
            cloud_ipv6_cidrs.add(e.get('ipv6Prefix'))
      print("google_ipv4_cidrs:")
      for i in goog_ipv4_cidrs.difference(cloud_ipv4_cidrs).iter_cidrs():
         print(' - "{}"'.format(i))
      print("google_ipv6_cidrs:")
      for i in goog_ipv6_cidrs.difference(cloud_ipv6_cidrs).iter_cidrs():
         print(' - "{}"'.format(i))

if __name__=='__main__':
   main()