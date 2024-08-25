#!/bin/perl -I/usr/local/lib/wifikey

require './wkfuncs.pm';

print "/", join("/", &hostapd_list), "/\n";
