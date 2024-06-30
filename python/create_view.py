#!/usr/bin/python

import time
import datetime
import warnings
import sys
import krest
from subprocess import call

'''
	This script is designed to take the latest snapshot of a given
	volume group and create a view. It will then map the view to a 
	host if provided by the user.
	
	.\create_view.py volume_group target_host 
								OR
	.\create_view.py volume_group
	
	NOTE:	Order is important. The volume group MUST be provided first.
'''

#	K2 Access Configuration
k2VIP = "172.17.0.120"
k2Username = "admin"
k2Password = "admin"

#	Ignore all warnings regarding HTTPS
warnings.filterwarnings("ignore")


##################################
##	Begin Function Definition	##
##################################
def printTimeStamp(msg):
    return str(time.strftime("%Y%m%d_%H%M%S")) + "-" + msg
	
def getVolume(ep):
	try:
		tVol = ep.get("volume_groups", ep.search("volume_groups", name=str(sys.argv[1])).hits[0].id)
	except:
		print "ERROR:	There has been an error in locating the desired volume group."
		print "Please verify and try again."
		sys.exit()
		
	return tVol
	
def getSnap(ep, targetVol):
	try:
		snapCount = ep.search("snapshots", source=targetVol).total
		tSnap = ep.get("snapshots", ep.search("snapshots", source=targetVol, __sort=id).hits[snapCount-1].id)
	except:
		print "ERROR:	There has been an error in locating the latest snapshot."
		print "Please verify and try again."
		sys.exit()
		
	return tSnap

def getHost(ep, view):
	#	First need to check if the host exists
	try:
		tHost = ep.get("hosts", ep.search("hosts", name=str(sys.argv[2])).hits[0].id)
	except:
		#	If the host, is part of a host group, will need to check that as well.
		return getHostGroup(ep, view)
		
		print "ERROR:	There has been an error in locating the target host/host group."
		print "Please verify and try again."
		sys.exit()
	
	return tHost

def getHostGroup(ep, view):
	try:
		ghHost = ep.get("host_groups", ep.search("host_groups", name=str(sys.argv[2])).hits[0].id)
	except:
		print "ERROR:	There has been an error in locating the target host/host group."
		print "Please verify and try again."
		sys.exit()

	return ghHost
	
def createView():
	ep = krest.EndPoint(k2VIP, k2Username, k2Password, ssl_validate=False)
	
	#	Obtain and verify volume group information provided by the user
	targetVol = getVolume(ep)
	latestSnap = getSnap(ep, targetVol)
	
	view = ep.new("snapshots")
	view.source = latestSnap
	view.short_name=latestSnap.short_name + "_V"
	retPol = latestSnap.retention_policy
	view.retention_policy = latestSnap.retention_policy
	view.is_exposable = True

	#	If a target host was provided
	if(len(sys.argv) == 3):
		newHost=getHost(ep, view)
		view.save()
		mapping = ep.new("mappings", volume=view, host=newHost).save()
	else:
		view.save()
	
	
##################
##	Main Script	##
##################
if (len(sys.argv) < 2 or len(sys.argv) > 3):
	print "Incorrect number of arguments provided. Please ensure that both a volume group (required) is provided along"
	print "with a target host (optional). Please note, the order is important. Please provide the volume group"
	print "first followed by the target host."
	print "Execution examples:"
	print "	.\create_view.py volume_group target_host"
	print "				OR"
	print "	.\create_view.py volume_group"
else:
	createView()
sys.exit()
