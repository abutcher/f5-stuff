#!/usr/bin/ruby
#
# == Synopsis
#
# f5_config_sync.rb - Synchronize your active and secondary load balancers.
#
# == Usage
#
# f5_config_sync [OPTIONS]
#
# -h, --help:
#    show help
#
# --bigip-address, -b [hostname]:
#    specify the destination BIG-IP
#
# --bigip-user, -u [username]:
#    username for destination BIG-IP
#
# --bigip-pass, -p [password]:
#    password for destination BIG-IP

require 'rubygems'
require 'f5-icontrol'
require 'getoptlong'
require 'rdoc/usage'
require "soap/wsdlDriver"

options = GetoptLong.new(
  [ '--bigip-address',    '-b', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--bigip-user',       '-u', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--bigip-pass',       '-p', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--help',             '-h', GetoptLong::NO_ARGUMENT ]
)

bigip_address = ''
bigip_user = ''
bigip_pass = ''

options.each do |option, arg|
  case option
    when '--bigip-address'
      bigip_address = arg
    when '--bigip-user'
      bigip_user = arg
    when '--bigip-pass'
      bigip_pass = arg
    when '--help'
      RDoc::usage
  end
end

RDoc::usage if bigip_address.empty? or bigip_user.empty? or bigip_pass.empty?

# Initiate SOAP RPC connection to BIG-IP
bigip = F5::IControl.new(bigip_address, bigip_user, bigip_pass, ['System.Failover', 'System.ConfigSync',]).get_interfaces

if bigip['System.Failover'].get_failover_state != 'FAILOVER_STATE_ACTIVE'
  puts "#{bigip_address} is not the active lb. Exiting!"
  exit 0
else
  puts 'Syncing configuring to standby...'
  bigip['System.ConfigSync'].synchronize_configuration('CONFIGSYNC_ALL')
  puts 'Configuration sync complete.'
end
