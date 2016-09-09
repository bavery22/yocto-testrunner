#!/usr/bin/python

# runtest.py
#
# Copyright (C) 2016 Intel Corporation
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

import argparse
import subprocess
import tempfile
import shutil
import os
import sys

scriptdir = os.path.dirname(os.path.realpath(__file__))

def preserve_artifacts(builddir, destdir, uid, removeimage=False):
    logsdir = "tmp/work/qemuppc-poky-linux/core-image-sato-sdk/1.0-r0/testimage"
    logsdir = os.path.join(builddir, logsdir)

    if removeimage:
        # Being lazy for glob
        image = os.path.join(logsdir, "*-testimage.*")
        subprocess.call("rm -f {}".format(image), shell=True)

    try:
        shutil.move(logsdir, destdir)
    except IOError:
        pass

    logsdir = "tmp/work/qemuppc-poky-linux/core-image-sato-sdk/1.0-r0/temp"
    logsdir = os.path.join(builddir, logsdir)
    try:
        shutil.move(logsdir, destdir)
    except IOError:
        pass

    # also save the target logs (dmesg, X0.log...)
    logsdir = "target_logs"
    logsdir = os.path.join(builddir, logsdir)
    try:
        shutil.move(logsdir, destdir)
    except IOError:
        pass

    try:
        shutil.move(os.path.join(builddir, "test-stdout"), os.path.join(destdir, "test-stdout"))
    except IOError:
        pass

    subprocess.call("chown -R {} {}".format(uid, destdir), shell=True)
    #  I'm not sure why I ever deleted the builddir, for now turn it off, but
    #  possibly make it an option in the future.
    #  subprocess.call("rm -rf {}".format(builddir), shell=True)

# Raise exception if the subprocess fails
def call_with_raise(cmd, logfile):
    with open(logfile, "a") as f:
        returncode = subprocess.call(cmd, stdout=f, stderr=f, shell=True)
        if returncode != 0:
            raise Exception("ExitError: {}".format(cmd))

parser = argparse.ArgumentParser()

parser.add_argument("--pokydir", default="/home/yoctouser/poky",
                     help="Directory containing poky")
parser.add_argument("--extraconf", action='append', help="File containing"
                    "extra configuration")
parser.add_argument("--builddir", help="Directory to build in")
parser.add_argument("--preservesuccess", action="store_true", help="Don't "
                    "remove directory if build is successful")
parser.add_argument("--removeimage", action="store_true", help="Remove image"
                    "from artifacts to save space")
parser.add_argument("--dontrenamefailures", action="store_true", help="Don't "
                    "rename directory if build is a failure")
parser.add_argument("--imagetotest", default="core-image-sato",
                    help = "core-image-sato by default.")
parser.add_argument("--deploydir", help="Directory that contains the images "
                    "directory and the rpm directory")
parser.add_argument("--testsuites", help="Comma separated"
                    "list of test suites to run.")
# uid is a remnant from before the container set up the permissions properly
# remove it later
parser.add_argument("--uid", default='{!s}'.format(os.getuid()), help='Numeric'
                    'uid of the owner of the artifacts.')
parser.add_argument("--outputprefix", default='testrun-')

args = parser.parse_args()

builddir = None

if not args.builddir:
    builddir = tempfile.mkdtemp(prefix=args.outputprefix, dir="/fromhost")
else:
    builddir = args.builddir

stdoutlog = os.path.join(builddir, "test-stdout")
if not os.path.isdir(builddir):
    os.makedirs(builddir)

try:
    extraconf = "{}/conf/testconf.inc".format(builddir)
    cmd = "mkdir -p {}/conf".format(builddir)
    call_with_raise(cmd, stdoutlog)

    with open(extraconf, "w") as f:
        if args.testsuites:
            testsuites = args.testsuites.replace(',', ' ')
            f.write("TEST_SUITES = \"{}\"\n".format(testsuites))

        if args.deploydir:
            f.write("DEPLOY_DIR = \"{}\"\n".format(args.deploydir))
#            f.write("DEPLOY_DIR_IMAGE = \"{}/images\"\n".format(args.deploydir))

        f.write("TESTIMAGE_DUMP_DIR = \"${TEST_LOG_DIR}\"\n")

        f.write("INHERIT += \"testimage\"\n")
        f.write("CONNECTIVITY_CHECK_URIS = \"\"\n")

    # USER isn't set on ubuntu when non-interactive, so set it, otherwise
    # vncserver complains.
    os.environ['USER'] = 'yoctouser'

    cmd = 'vncserver :1'
    call_with_raise(cmd, stdoutlog)

    os.environ['DISPLAY'] = ':1'

    bbtarget = "\"{} -c testimage\"".format(args.imagetotest)
    runbitbake = "{}/runbitbake.py".format(scriptdir)

    cmd = "{} --pokydir={} --extraconf={} -t {} -b {}".format(runbitbake, args.pokydir,
                                   extraconf, bbtarget, builddir)
    if args.extraconf:
        allextraconf = " ".join(["--extraconf={}".format(x) for x in args.extraconf])
        cmd += " {}".format(allextraconf)

    call_with_raise(cmd, stdoutlog)

except Exception as e:
    finaldir = tempfile.mkdtemp(prefix=args.outputprefix, dir="/fromhost",
                                suffix="-failure")
    preserve_artifacts(builddir, finaldir, args.uid, args.removeimage)

    raise e, None, sys.exc_info()[2]

finally:
    subprocess.call("vncserver -kill :1", shell=True)

if args.preservesuccess:
    finaldir = tempfile.mkdtemp(prefix=args.outputprefix, dir="/fromhost")
    preserve_artifacts(builddir, finaldir, args.uid, args.removeimage)
