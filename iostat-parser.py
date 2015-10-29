#!/usr/bin/python

import re
import sys
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("logfile")
parser.add_argument("device", nargs="+",
                    help = "Device to include in summary")

args = parser.parse_args()

stats = {}

for device in args.device:
    stats[device.strip()] = {}
    stats[device.strip()]["util"] = []
    stats[device]["total"] = 0

with open (args.logfile, "r") as logfile:
    for line in logfile:
        if not re.match(r'^\d+/\d+/\d+ ', line) and \
               not line.startswith("Device:") and \
               not line.startswith("Linux ") and \
               not re.match(r'^\s*$', line):
            device = line.split(' ', 1)[0]
            util = float(line.rsplit(' ', 1)[1])
            if device in stats:
                stats[device]["util"].append(util)
                stats[device]["total"] += util


for key in stats:
    stats[key]["util"].sort()
    count = len(stats[key]["util"])
    print "{}:".format(key)
    if stats[key]["total"] != 0:
        print "       AVG: {}".format(stats[key]["total"]/count)
    if count != 0:
        # Yeah not truly the median, but tough.
        print "    MEDIAN: {}".format(stats[key]["util"][count/2])
