#!/usr/bin/ruby
#
# == Synopsis
#
# check_f5_pool - Check the active percentage of specified f5 pool.
#
# == Usage
#
# check_f5_pool [OPTIONS]
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
#
# --critical-pct, -c [pct]:
#   Critical threshold for critical alert, example: 50
#
# --partition, -f [partition]
#   Partition in which pool exists
#
# --pool-name, -n [name]: 
#    name of pool to query
#
# --warning-pct, -w [pct]:
#   Warning threshold for warning alert, example: 90
#

require 'rubygems'
require 'f5-icontrol'
require 'getoptlong'
require 'rdoc/usage'

options = GetoptLong.new(
  [ '--bigip-address',    '-b', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--bigip-user',       '-u', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--bigip-pass',       '-p', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--pool-name',        '-n', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--warning-pct',      '-w', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--critical-pct',     '-c', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--partition',        '-f', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--help',             '-h', GetoptLong::NO_ARGUMENT ]
)

bigip_address = ''
bigip_user = ''
bigip_pass = ''
pool_name = ''
warning_pct = 75
critical_pct = 50
partition = ''

options.each do |option, arg|
  case option
    when '--bigip-address'
      bigip_address = arg
    when '--bigip-user'
      bigip_user = arg
    when '--bigip-pass'
      bigip_pass = arg
    when '--pool-name'
      pool_name = arg.upcase
    when '--warning_pct'
      warning_pct = arg
    when '--critical_pct'
      critical_pct = arg
    when '--partition'
      partition = arg.upcase
    when '--help'
      RDoc::usage
  end
end

RDoc::usage if bigip_address.empty? or bigip_user.empty? or bigip_pass.empty? or pool_name.empty? or partition.empty?

# Initiate SOAP RPC connection to BIG-IP
bigip = F5::IControl.new(bigip_address, bigip_user, bigip_pass, ['LocalLB.Pool', 'LocalLB.PoolMember', 'Management.Partition']).get_interfaces

# Set the active partition
bigip['Management.Partition'].set_active_partition( partition )

# Ensure that target pool exists
unless bigip['LocalLB.Pool'].get_list.include? pool_name
  puts 'UNKNOWN: F5 target pool "' + pool_name +'" does not exist'
  exit -1
end

# Get list of pool members with their address, port, and status
members = bigip['LocalLB.PoolMember'].get_monitor_status( [pool_name] )[0].collect do |member|
  { :address => member['member']['address'],
    :port => member['member']['port'],
    :status => member['monitor_status'] }
end

monitors = bigip['LocalLB.PoolMember'].get_monitor_instance( [pool_name] )[0].collect do |member|
  member['monitor_instances'].map { |instance| { :address => member['member']['address'], 
      :port => member['member']['port'],
      :name => instance['instance']['template_name'],
      :status => instance['instance_state'] }}
end

# Determine which members are up, which are down (but haven't been
# manually disabled) and which have been manually disabled
active_members = members.find_all { |member| member[:status].include? 'UP' }
down_members = members.find_all { |member| member[:status].include? 'DOWN' and not member[:status].include? 'WAIT_FOR_MANUAL_RESUME' }
maint_members = members.find_all { |member| member[:status].include? 'WAIT_FOR_MANUAL_RESUME' }

# Get the counts, don't include maintenance members
member_count = members.length - maint_members.length
active_member_count = active_members.length

# Tally that up
if member_count == 0
  pool_up_pct = 0
else
  pool_up_pct = (active_member_count / member_count) * 100
end

# Collect virtual servers that are down
down_msg = ''
if down_members.length != 0
  down_msg = "\nDown Members:"
  down_members.each do |member|
    monitor = monitors.find_all { |monitor| monitor[0][:address] == member[:address] and monitor[0][:port] == member[:port] and monitor[0][:status].include? 'DOWN' }.map { |monitor| monitor[0][:name] }
    down_msg += "\n#{member[:address]}:#{member[:port]} (#{monitor})"
  end
end

# Output appropriate message w/ exit code
if pool_up_pct <= critical_pct
  puts "CRITICAL: F5 Pool #{pool_name}, #{active_member_count} of #{member_count} pool members active." \
  + down_msg + "\nF5 Link: https://#{bigip_address}"
  exit 2
elsif pool_up_pct <= warning_pct
  puts "WARNING: F5 Pool #{pool_name}, #{active_member_count} of #{member_count} pool members active." \
  + down_msg + "\nF5 Link: https://#{bigip_address}"
  exit 1
elsif pool_up_pct >= warning_pct
  puts "OK: F5 Pool #{pool_name}, #{active_member_count} of #{member_count} pool members active." \
  + down_msg + "\nF5 Link: https://#{bigip_address}"
  exit 0
end
